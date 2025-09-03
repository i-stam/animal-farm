#!/usr/bin/env python3
"""
FarmBot Daemon - Monitors Aave USDC APR and executes swaps when profitable
"""

import os
import json
import time
import logging
from typing import Optional
from decimal import Decimal
from dotenv import load_dotenv
from web3 import Web3
from web3.contract import Contract
from eth_account import Account

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('farmbot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class FarmBot:
    """Main FarmBot daemon class"""

    def __init__(self):
        # Load configuration
        self.rpc_url = os.getenv('RPC_URL')
        self.private_key = os.getenv('PRIVATE_KEY')
        self.contract_address = os.getenv('FARMBOT_CONTRACT_ADDRESS')

        # Validation
        if not self.private_key:
            raise ValueError("PRIVATE_KEY environment variable is required")
        if not self.contract_address:
            raise ValueError("FARMBOT_CONTRACT_ADDRESS environment variable is required")

        # Web3 setup
        self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        if not self.w3.is_connected():
            raise ConnectionError(f"Failed to connect to {self.rpc_url}")

        # Account setup
        self.account = Account.from_key(self.private_key)
        self.address = self.account.address

        # Contract setup
        self.contract = self._load_contract()

        # Configuration
        self.poll_interval = int(os.getenv('POLL_INTERVAL', 300))  # 5 minutes default
        self.max_gas_price = int(os.getenv('MAX_GAS_PRICE', 50))  # 50 gwei default
        self.min_eth_balance = Decimal(os.getenv('MIN_ETH_BALANCE', '0.1'))  # Keep 0.1 ETH for gas
        self.slippage_tolerance = Decimal(os.getenv('SLIPPAGE_TOLERANCE', '0.05'))  # 5% slippage

        logger.info(f"FarmBot initialized for address: {self.address}")
        logger.info(f"Contract address: {self.contract_address}")
        logger.info(f"Poll interval: {self.poll_interval} seconds")

    def _load_contract(self) -> Contract:
        """Load the FarmBot contract ABI and return contract instance"""

        # FarmBot contract ABI (minimal required functions)
        # Also update README with correct USDC address
        abi = json.loads('''[
            {
                "inputs": [],
                "name": "getCurrentUSDCApr",
                "outputs": [{"type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [],
                "name": "shouldExecute",
                "outputs": [{"type": "bool"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [{"type": "uint256"}, {"type": "uint256"}],
                "name": "executeIfProfitable",
                "outputs": [],
                "stateMutability": "payable",
                "type": "function"
            },
            {
                "inputs": [],
                "name": "getStatus",
                "outputs": [
                    {"type": "uint256"},
                    {"type": "bool"},
                    {"type": "uint256"},
                    {"type": "uint256"}
                ],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [],
                "name": "defaultSwapAmount",
                "outputs": [{"type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [{"type": "uint256"}],
                "name": "rayToApr",
                "outputs": [{"type": "uint256"}],
                "stateMutability": "pure",
                "type": "function"
            }
        ]''')

        return self.w3.eth.contract(
            address=Web3.to_checksum_address(self.contract_address),
            abi=abi
        )

    def get_gas_price(self) -> int:
        """Get current gas price with max limit"""
        try:
            gas_price = self.w3.eth.gas_price
            max_gas_price_wei = self.w3.to_wei(self.max_gas_price, 'gwei')
            return min(gas_price, max_gas_price_wei)
        except Exception as e:
            logger.error(f"Failed to get gas price: {e}")
            return self.w3.to_wei(20, 'gwei')  # Fallback to 20 gwei

    def get_eth_balance(self) -> Decimal:
        """Get ETH balance in ether"""
        balance_wei = self.w3.eth.get_balance(self.address)
        return Decimal(self.w3.from_wei(balance_wei, 'ether'))

    def get_status(self) -> dict:
        """Get contract status"""
        try:
            current_apr, should_exec, eth_balance, usdc_balance = self.contract.functions.getStatus().call()
            return {
                'current_apr': current_apr,
                'current_apr_percentage': current_apr / 100,
                'should_execute': should_exec,
                'contract_eth_balance': self.w3.from_wei(eth_balance, 'ether'),
                'contract_usdc_balance': usdc_balance / 1e6,  # USDC has 6 decimals
                'account_eth_balance': float(self.get_eth_balance())
            }
        except Exception as e:
            logger.error(f"Failed to get contract status: {e}")
            return {}

    def estimate_usdc_output(self, eth_amount: Decimal) -> Decimal:
        """Estimate USDC output from ETH (rough estimate using price feeds if available)"""
        # This is a simplified estimate - in production you'd want to use
        # Uniswap quoter contract or price feeds for accurate estimates
        eth_price_usd = 2500  # Rough estimate, should be dynamic
        usdc_amount = eth_amount * Decimal(eth_price_usd)
        return usdc_amount * (Decimal('1') - self.slippage_tolerance)

    def execute_swap(self) -> bool:
        """Execute the swap if conditions are met"""
        try:
            # Check if we should execute
            should_execute = self.contract.functions.shouldExecute().call()
            if not should_execute:
                logger.info("APR threshold not met, skipping execution")
                return False

            # Get default swap amount from contract
            default_swap_amount = self.contract.functions.defaultSwapAmount().call()
            eth_amount = Decimal(self.w3.from_wei(default_swap_amount, 'ether'))

            # Check our ETH balance
            account_balance = self.get_eth_balance()
            required_balance = eth_amount + self.min_eth_balance + Decimal('0.05')  # Extra for gas

            if account_balance < required_balance:
                logger.warning(f"Insufficient ETH balance. Have: {account_balance}, Need: {required_balance}")
                return False

            # Estimate minimum USDC output
            min_usdc_out = self.estimate_usdc_output(eth_amount)
            min_usdc_out_wei = int(min_usdc_out * Decimal('1e6'))  # USDC has 6 decimals

            # Prepare transaction
            gas_price = self.get_gas_price()

            # Estimate gas
            try:
                gas_estimate = self.contract.functions.executeIfProfitable(
                    default_swap_amount,
                    min_usdc_out_wei
                ).estimate_gas({
                    'from': self.address,
                    'value': default_swap_amount
                })
                gas_limit = int(gas_estimate * 1.2)  # Add 20% buffer
            except Exception as e:
                logger.error(f"Gas estimation failed: {e}")
                gas_limit = 500000  # Fallback gas limit

            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.address)

            transaction = self.contract.functions.executeIfProfitable(
                default_swap_amount,
                min_usdc_out_wei
            ).build_transaction({
                'from': self.address,
                'value': default_swap_amount,
                'gas': gas_limit,
                'gasPrice': gas_price,
                'nonce': nonce
            })

            # Sign and send transaction
            signed_txn = self.account.sign_transaction(transaction)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.rawTransaction)

            logger.info(f"Transaction sent: {tx_hash.hex()}")
            logger.info(f"ETH Amount: {eth_amount}, Min USDC: {min_usdc_out}")

            # Wait for confirmation
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=300)

            if receipt['status'] == 1:
                logger.info(f"✅ Swap executed successfully! Gas used: {receipt['gasUsed']}")
                return True
            else:
                logger.error("❌ Transaction failed")
                return False

        except Exception as e:
            logger.error(f"Failed to execute swap: {e}")
            return False

    def run_once(self) -> None:
        """Run one iteration of the bot"""
        logger.info("=== FarmBot Check ===")

        # Get current status
        status = self.get_status()
        if not status:
            logger.error("Failed to get contract status")
            return

        logger.info(f"Current USDC APR: {status['current_apr_percentage']:.2f}%")
        logger.info(f"Should execute: {status['should_execute']}")
        logger.info(f"Account ETH balance: {status['account_eth_balance']:.4f} ETH")
        logger.info(f"Contract ETH balance: {status['contract_eth_balance']:.4f} ETH")
        logger.info(f"Contract USDC balance: {status['contract_usdc_balance']:.2f} USDC")

        # Execute if conditions are met
        if status['should_execute']:
            logger.info("🚀 Conditions met! Executing swap...")
            success = self.execute_swap()
            if success:
                logger.info("✅ Swap completed successfully!")
            else:
                logger.error("❌ Swap execution failed")
        else:
            logger.info("⏳ Waiting for better APR conditions...")

    def run_daemon(self) -> None:
        """Run the bot daemon continuously"""
        logger.info("🤖 FarmBot daemon starting...")

        try:
            while True:
                self.run_once()
                logger.info(f"💤 Sleeping for {self.poll_interval} seconds...")
                time.sleep(self.poll_interval)

        except KeyboardInterrupt:
            logger.info("👋 FarmBot daemon stopped by user")
        except Exception as e:
            logger.error(f"💥 FarmBot daemon crashed: {e}")
            raise


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='FarmBot - Aave/Uniswap Farming Bot')
    parser.add_argument('--once', action='store_true', help='Run once instead of daemon mode')
    parser.add_argument('--status', action='store_true', help='Show status and exit')

    args = parser.parse_args()

    try:
        bot = FarmBot()

        if args.status:
            status = bot.get_status()
            print(json.dumps(status, indent=2, default=str))
        elif args.once:
            bot.run_once()
        else:
            bot.run_daemon()

    except Exception as e:
        logger.error(f"Failed to start FarmBot: {e}")
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
