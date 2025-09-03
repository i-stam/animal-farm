# FarmBot - Aave/Uniswap Automated Farming Bot

An automated bot that monitors Aave V3 USDC APR and executes profitable ETH→USDC swaps + deposits when APR exceeds 5%.

## Features

- 🤖 **Automated Monitoring**: Polls Aave USDC APR every 5 minutes
- 💱 **Smart Swapping**: Uses Uniswap V3 for optimal ETH→USDC swaps
- 🏦 **Auto Deposits**: Automatically deposits USDC to Aave V3 for yield
- ⚡ **Gas Optimized**: Batches swap and deposit in single transaction
- 🛡️ **Safety Features**: APR thresholds, slippage protection, owner controls
- 🔍 **Fork Testing**: Comprehensive tests on mainnet fork

## Architecture

### Smart Contracts
- **FarmBot.sol**: Main contract that batches Uniswap swaps and Aave deposits
- **Interfaces**: Clean interfaces for Aave V3 and Uniswap V3 integration

### Python Bot
- **bot.py**: Daemon that monitors APR and triggers contract execution
- **Requirements**: Web3.py, python-dotenv for blockchain interaction

## Quick Start

### 1. Install Dependencies

```bash
# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# - Add your Alchemy API key
# - Add your private key (use a dedicated wallet!)
# - Add Etherscan API key for verification
```

### 3. Test on Fork

```bash
# Run tests on mainnet fork (requires .env file with RPC_URL)
forge test -vv

# Test specific function
forge test --match-test testForceExecute -vvv

# Tests automatically fork mainnet using vm.createFork() in setUp()
```

### 4. Deploy Contract

```bash
# Deploy to mainnet (be careful!)
forge script script/DeployFarmBot.s.sol:DeployFarmBotScript --rpc-url mainnet --private-key $PRIVATE_KEY --broadcast --verify

# Or deploy to testnet first
forge script script/DeployFarmBot.s.sol:DeployFarmBotScript --rpc-url goerli --private-key $PRIVATE_KEY --broadcast --verify
```

### 5. Run Bot

```bash
# Check current status
python bot.py --status

# Run once
python bot.py --once

# Run as daemon
python bot.py
```

## Configuration

### Smart Contract Settings

- **Default Swap Amount**: 5 ETH
- **APR Threshold**: 5% (500 basis points)
- **Pool Fee**: 0.3% (Uniswap V3)

Update via `updateConfig()` function (owner only).

### Bot Settings

Configure in `.env`:

- `POLL_INTERVAL`: How often to check APR (default: 300 seconds)
- `MAX_GAS_PRICE`: Maximum gas price in gwei (default: 50)
- `MIN_ETH_BALANCE`: ETH to reserve for gas (default: 0.1)
- `SLIPPAGE_TOLERANCE`: Swap slippage tolerance (default: 5%)

## Contract Addresses (Mainnet)

- **Aave V3 Pool**: `0x87870Bced4D87A94a3DB5B2067b8daCf0e8cc06c`
- **Uniswap V3 Router**: `0xE592427A0AEce92De3Edee1F18E0157C05861564`
- **USDC**: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- **WETH9**: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`

## Testing

### Run All Tests

```bash
forge test -vv
```

### Specific Test Categories

```bash
# Test APR checking
forge test --match-test testGetCurrentUSDCApr -vv

# Test execution logic  
forge test --match-test testExecuteIfProfitable -vv

# Test emergency functions
forge test --match-test testEmergency -vv
```

## Security Considerations

⚠️ **IMPORTANT SECURITY NOTES**:

1. **Dedicated Wallet**: Use a dedicated wallet for the bot, not your main wallet
2. **Limited Funds**: Only keep necessary ETH for operations
3. **Test First**: Always test on testnet/fork before mainnet
4. **Monitor Gas**: High gas prices can eat into profits
5. **Private Key**: Never commit private keys to version control
6. **Contract Ownership**: Verify you own the deployed contract

## Bot Operations

### Manual Operations

```bash
# Check contract status
python bot.py --status

# Run bot once (useful for testing)
python bot.py --once
```

### Daemon Mode

```bash
# Run continuously (recommended for production)
python bot.py

# Run in background with logging
nohup python bot.py > farmbot.log 2>&1 &
```

### Emergency Controls

The smart contract includes emergency functions (owner only):

- `emergencyWithdraw()`: Withdraw ETH or ERC20 tokens
- `updateConfig()`: Update swap amount and APR threshold
- `transferOwnership()`: Transfer contract ownership

## Monitoring

### Logs

The bot creates detailed logs in:
- Console output (real-time)
- `farmbot.log` file (persistent)

### Status Monitoring

```bash
# Get detailed status
python bot.py --status

# Monitor logs
tail -f farmbot.log
```

### Key Metrics

- Current USDC APR
- ETH balance (account and contract)
- USDC/aUSDC balance
- Gas prices
- Execution success/failure rates

## Troubleshooting

### Common Issues

1. **"APR threshold not met"**: APR is below 5%, bot is waiting
2. **"Insufficient ETH balance"**: Add more ETH to your account
3. **High gas prices**: Adjust `MAX_GAS_PRICE` in `.env`
4. **RPC errors**: Check your Alchemy API key and limits

### Debug Mode

Run with verbose logging:
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
python bot.py --once
```

## Future Improvements

Potential enhancements for future versions:

1. **Multi-token support**: Support other assets beyond USDC
2. **Dynamic thresholds**: Adjust APR thresholds based on market conditions  
3. **Better price feeds**: Use Chainlink oracles for accurate pricing
4. **Compound strategies**: Reinvest earned interest
5. **Risk management**: Stop-loss and take-profit mechanisms
6. **Web interface**: Dashboard for monitoring and controls

## License

MIT License - see LICENSE file for details.

## Disclaimer

This software is for educational purposes. Use at your own risk. The authors are not responsible for any financial losses. Always test thoroughly before using with real funds.