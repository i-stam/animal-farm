// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IAaveV3Pool.sol";
import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH9.sol";

contract FarmBot {
    address public owner;
    
    // Mainnet addresses
    address public constant AAVE_V3_POOL = 0x87870BceD4D87a94a3DB5B2067b8daCF0e8cc06c;
    address public constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // Configuration
    uint256 public defaultSwapAmount = 5 ether;
    uint256 public aprThreshold = 500; // 5% in basis points (5 * 100)
    uint24 public constant POOL_FEE = 3000; // 0.3% pool fee
    
    // Events
    event SwapAndDeposit(uint256 ethAmount, uint256 usdcReceived, uint256 aprRate);
    event ConfigUpdated(uint256 newSwapAmount, uint256 newAprThreshold);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Get current USDC APR from Aave V3
     * @return Current liquidity rate in ray (27 decimals)
     */
    function getCurrentUSDCApr() public view returns (uint256) {
        IAaveV3Pool aavePool = IAaveV3Pool(AAVE_V3_POOL);
        IAaveV3Pool.ReserveData memory reserveData = aavePool.getReserveData(USDC);
        return reserveData.currentLiquidityRate;
    }
    
    /**
     * @dev Convert ray rate to APR percentage (basis points)
     * @param rate Rate in ray format
     * @return APR in basis points (e.g., 500 = 5%)
     */
    function rayToApr(uint256 rate) public pure returns (uint256) {
        // Ray is 27 decimals, convert to basis points (4 decimals for percentage)
        // APR = rate / 1e27 * 100 * 100 = rate / 1e23
        return rate / 1e23;
    }
    
    /**
     * @dev Check if current APR meets threshold
     * @return true if APR >= threshold
     */
    function shouldExecute() external view returns (bool) {
        uint256 currentRate = getCurrentUSDCApr();
        uint256 currentApr = rayToApr(currentRate);
        return currentApr >= aprThreshold;
    }
    
    /**
     * @dev Execute swap and deposit if APR condition is met
     * @param ethAmount Amount of ETH to swap (use 0 for default)
     * @param minUsdcOut Minimum USDC to receive from swap
     */
    function executeIfProfitable(uint256 ethAmount, uint256 minUsdcOut) external payable onlyOwner {
        require(this.shouldExecute(), "APR threshold not met");
        
        uint256 amountToSwap = ethAmount > 0 ? ethAmount : defaultSwapAmount;
        require(msg.value >= amountToSwap, "Insufficient ETH sent");
        
        // Execute the swap and deposit
        uint256 usdcReceived = _swapAndDeposit(amountToSwap, minUsdcOut);
        
        // Refund excess ETH
        if (msg.value > amountToSwap) {
            payable(msg.sender).transfer(msg.value - amountToSwap);
        }
        
        emit SwapAndDeposit(amountToSwap, usdcReceived, rayToApr(getCurrentUSDCApr()));
    }
    
    /**
     * @dev Force execute swap and deposit (bypass APR check)
     * @param ethAmount Amount of ETH to swap (use 0 for default)
     * @param minUsdcOut Minimum USDC to receive from swap
     */
    function forceExecute(uint256 ethAmount, uint256 minUsdcOut) external payable onlyOwner {
        uint256 amountToSwap = ethAmount > 0 ? ethAmount : defaultSwapAmount;
        require(msg.value >= amountToSwap, "Insufficient ETH sent");
        
        uint256 usdcReceived = _swapAndDeposit(amountToSwap, minUsdcOut);
        
        if (msg.value > amountToSwap) {
            payable(msg.sender).transfer(msg.value - amountToSwap);
        }
        
        emit SwapAndDeposit(amountToSwap, usdcReceived, rayToApr(getCurrentUSDCApr()));
    }
    
    /**
     * @dev Internal function to swap ETH for USDC and deposit to Aave
     * @param ethAmount Amount of ETH to swap
     * @param minUsdcOut Minimum USDC to receive
     * @return usdcReceived Amount of USDC received and deposited
     */
    function _swapAndDeposit(uint256 ethAmount, uint256 minUsdcOut) internal returns (uint256 usdcReceived) {
        IUniswapV3Router router = IUniswapV3Router(UNISWAP_V3_ROUTER);
        
        // Swap ETH for USDC
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: USDC,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp + 300, // 5 minutes
            amountIn: ethAmount,
            amountOutMinimum: minUsdcOut,
            sqrtPriceLimitX96: 0
        });
        
        usdcReceived = router.exactInputSingle{value: ethAmount}(params);
        
        // Approve USDC for Aave
        IERC20(USDC).approve(AAVE_V3_POOL, usdcReceived);
        
        // Deposit USDC to Aave
        IAaveV3Pool(AAVE_V3_POOL).supply(USDC, usdcReceived, address(this), 0);
        
        return usdcReceived;
    }
    
    /**
     * @dev Update configuration
     * @param newSwapAmount New default swap amount
     * @param newAprThreshold New APR threshold in basis points
     */
    function updateConfig(uint256 newSwapAmount, uint256 newAprThreshold) external onlyOwner {
        require(newSwapAmount > 0, "Invalid swap amount");
        require(newAprThreshold > 0, "Invalid APR threshold");
        
        defaultSwapAmount = newSwapAmount;
        aprThreshold = newAprThreshold;
        
        emit ConfigUpdated(newSwapAmount, newAprThreshold);
    }
    
    /**
     * @dev Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
    
    /**
     * @dev Emergency function to withdraw tokens
     * @param token Token address to withdraw
     * @param amount Amount to withdraw (0 for full balance)
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            // Withdraw ETH
            uint256 balance = address(this).balance;
            uint256 withdrawAmount = amount > 0 ? amount : balance;
            payable(owner).transfer(withdrawAmount);
        } else {
            // Withdraw ERC20
            IERC20 tokenContract = IERC20(token);
            uint256 balance = tokenContract.balanceOf(address(this));
            uint256 withdrawAmount = amount > 0 ? amount : balance;
            tokenContract.transfer(owner, withdrawAmount);
        }
    }
    
    /**
     * @dev Get contract status
     * @return currentApr Current USDC APR in basis points
     * @return shouldExec Whether execution should proceed
     * @return ethBalance Contract ETH balance
     * @return usdcBalance Contract USDC balance
     */
    function getStatus() external view returns (
        uint256 currentApr,
        bool shouldExec,
        uint256 ethBalance,
        uint256 usdcBalance
    ) {
        currentApr = rayToApr(getCurrentUSDCApr());
        shouldExec = currentApr >= aprThreshold;
        ethBalance = address(this).balance;
        usdcBalance = IERC20(USDC).balanceOf(address(this));
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
}