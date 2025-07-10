// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface INonfungiblePositionManager {
    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );
    
    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function burn(uint256 tokenId) external payable;
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
}

interface IUniswapV3Router {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
}

struct DecreaseLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
    uint256 amount0Min;
    uint256 amount1Min;
    uint256 deadline;
}

struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
}

contract DefiSalmon {
    // Sepolia Testnet Addresses
    address public constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // Sepolia WETH
    address public constant USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Sepolia USDT
    address public constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Sepolia ETH/USD
    address public constant POSITION_MANAGER = 0x1238536071E1c677A632429e3655c799b22cDA52; // Sepolia Uniswap V3
    address public constant UNISWAP_V3_ROUTER = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E; // Sepolia Router
    address public constant WETH_USDT_POOL = 0x4c36388bE6F416a29c8D8Ed537638c7d6C5c2c1c; // Sepolia WETH/USDT 0.05%
    
    // Lending Configuration
    uint256 public constant MAX_LTV = 70; // 70% max loan-to-value ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80% liquidation threshold
    
    mapping(address => mapping(address => uint256)) public userDeposits; // user -> token -> amount
    mapping(address => uint256) public userNFT; // Only one NFT per user
    mapping(uint256 => address) public nftOwner;
    mapping(address => uint256) public userBorrows; // user -> total debt in USD (scaled by 1e6)
    
    // FIXED: Remove automatic decimal multiplication - users provide exact amounts
    function deposit(string memory token, uint256 amount) external {
        require(amount > 0, "Amount must be positive");
        
        if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("weth"))) {
            require(IERC20(WETH).transferFrom(msg.sender, address(this), amount), "WETH transfer failed");
            userDeposits[msg.sender][WETH] += amount;
        } else if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("usdt"))) {
            require(IERC20(USDT).transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
            userDeposits[msg.sender][USDT] += amount;
        } else {
            revert("Use 'weth' or 'usdt'");
        }
    }
    
    function depositV3Pos(uint256 tokenId) external {
        require(userNFT[msg.sender] == 0, "Already have an NFT");
        (,, address token0, address token1,,,,,,,,) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);
        require((token0 == WETH && token1 == USDT) || (token0 == USDT && token1 == WETH), "Only WETH/USDT positions");
        IERC721(POSITION_MANAGER).transferFrom(msg.sender, address(this), tokenId);
        userNFT[msg.sender] = tokenId;
        nftOwner[tokenId] = msg.sender;
    }
    
    function withdraw(address token, uint256 amount) external {
        require(token == WETH || token == USDT, "Invalid token");
        require(userDeposits[msg.sender][token] >= amount, "Insufficient balance");
        
        // Check if withdrawal would make user undercollateralized
        uint256 newCollateralValue = getCollateralValueAfterWithdrawal(msg.sender, token, amount);
        uint256 debt = userBorrows[msg.sender];
        if (debt > 0) {
            require(debt * 100 <= newCollateralValue * MAX_LTV, "Would exceed max LTV");
        }
        
        userDeposits[msg.sender][token] -= amount;
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }
    
    // FIXED: Add proper borrowing limits and collateral checks
    function borrow(uint256 amount) external {
        require(amount > 0, "Amount must be positive");
        uint256 collateralValue = getCollateralValue(msg.sender);
        require(collateralValue > 0, "No collateral");
        
        uint256 newDebt = userBorrows[msg.sender] + amount;
        require(newDebt * 100 <= collateralValue * MAX_LTV, "Exceeds max LTV ratio");
        
        userBorrows[msg.sender] = newDebt;
        
        // TODO: Actually mint/transfer borrowed USDT to user
        // For now, this is just tracking debt
    }
    
    function getCollateralValue(address user) public view returns (uint256) {
        uint256 wethValue = (userDeposits[user][WETH] * getETHPrice()) / 1e8 / 1e12; // Convert to USD with 6 decimals
        uint256 usdtValue = userDeposits[user][USDT]; // Already in 6 decimals
        uint256 nftValue = getUserNFTValue(user);
        return wethValue + usdtValue + nftValue;
    }
    
    function getCollateralValueAfterWithdrawal(address user, address token, uint256 amount) internal view returns (uint256) {
        uint256 wethBalance = userDeposits[user][WETH];
        uint256 usdtBalance = userDeposits[user][USDT];
        
        if (token == WETH) {
            wethBalance -= amount;
        } else {
            usdtBalance -= amount;
        }
        
        uint256 wethValue = (wethBalance * getETHPrice()) / 1e8 / 1e12;
        uint256 usdtValue = usdtBalance;
        uint256 nftValue = getUserNFTValue(user);
        return wethValue + usdtValue + nftValue;
    }
    
    function getUserNFTValue(address user) internal view returns (uint256) {
        uint256 tokenId = userNFT[user];
        if (tokenId == 0) {
            return 0;
        }
        return getNFTValue(tokenId);
    }
    
    // SIMPLIFIED: Basic NFT valuation - for production, use proper Uniswap V3 math
    function getNFTValue(uint256 tokenId) public view returns (uint256) {
        (,, address token0, address token1,, int24 tickLower, int24 tickUpper, uint128 liquidity,,, uint128 tokensOwed0, uint128 tokensOwed1) = 
            INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);
        
        // Simplified calculation - estimate 50/50 value split for demo
        // In production, use proper tick math
        uint256 totalLiquidity = uint256(liquidity);
        if (totalLiquidity == 0) return 0;
        
        uint256 ethPrice = getETHPrice();
        
        // Rough estimation: assume liquidity represents equal USD value in both tokens
        uint256 estimatedUSDValue = (totalLiquidity * ethPrice) / 1e8 / 1e12;
        
        // Add uncollected fees (rough conversion)
        uint256 fee0Value = token0 == WETH ? 
            (uint256(tokensOwed0) * ethPrice) / 1e8 / 1e12 : 
            uint256(tokensOwed0);
        uint256 fee1Value = token1 == WETH ? 
            (uint256(tokensOwed1) * ethPrice) / 1e8 / 1e12 : 
            uint256(tokensOwed1);
            
        return estimatedUSDValue + fee0Value + fee1Value;
    }
    
    function getETHPrice() public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_FEED).latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }
    
    function repay(uint256 amount) external {
        require(amount > 0, "Amount must be positive");
        require(userBorrows[msg.sender] >= amount, "Repaying more than owed");
        userBorrows[msg.sender] -= amount;
        
        // TODO: Actually transfer USDT from user to repay
    }
    
    // --- Liquidation Step 1: Close NFT Position ---
    function closeNFTPosition(address user) external {
        require(userNFT[user] != 0, "No NFT to close");
        require(_isLiquidatable(user), "Not liquidatable");
        uint256 tokenId = userNFT[user];
        
        // Get minimal position data
        (,, address token0,,,,,uint128 liquidity,,,,) = 
            INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);
        
        // Decrease liquidity
        INonfungiblePositionManager npm = INonfungiblePositionManager(POSITION_MANAGER);
        npm.decreaseLiquidity(DecreaseLiquidityParams(tokenId, liquidity, 0, 0, block.timestamp + 300));
        
        // Collect tokens
        (uint256 amount0, uint256 amount1) = npm.collect(CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max));
        
        // Burn NFT
        npm.burn(tokenId);
        
        // Credit user
        if (token0 == WETH) {
            userDeposits[user][WETH] += amount0;
            userDeposits[user][USDT] += amount1;
        } else {
            userDeposits[user][WETH] += amount1;
            userDeposits[user][USDT] += amount0;
        }
        
        userNFT[user] = 0;
        delete nftOwner[tokenId];
    }

    // FIXED: Improved liquidation logic with proper proceeds handling
    function sellCollateral(address user) external returns (uint256 proceeds) {
        require(userNFT[user] == 0, "NFT must be closed first");
        require(_isLiquidatable(user), "Not liquidatable");
        
        uint256 wethBalance = userDeposits[user][WETH];
        uint256 usdtBalance = userDeposits[user][USDT];
        uint256 debt = userBorrows[user];
        
        // Convert WETH to USDT if needed to cover debt
        if (debt > usdtBalance && wethBalance > 0) {
            uint256 wethToSell = wethBalance;
            uint256 usdtReceived = sellWETHForUSDT(wethToSell);
            userDeposits[user][WETH] = 0;
            userDeposits[user][USDT] += usdtReceived;
            usdtBalance += usdtReceived;
        }
        
        // Repay debt and calculate proceeds
        if (debt > 0) {
            if (usdtBalance >= debt) {
                proceeds = usdtBalance - debt;
                userDeposits[user][USDT] = 0;
            } else {
                // Partial repayment
                proceeds = 0;
                userDeposits[user][USDT] = 0;
                userBorrows[user] = debt - usdtBalance;
            }
        } else {
            proceeds = usdtBalance;
            userDeposits[user][USDT] = 0;
        }
        
        // Clear remaining collateral
        userDeposits[user][WETH] = 0;
        if (debt <= usdtBalance) {
            userBorrows[user] = 0;
        }
        
        // Transfer proceeds to liquidator
        if (proceeds > 0) {
            require(IERC20(USDT).transfer(msg.sender, proceeds), "Proceeds transfer failed");
        }
        
        return proceeds;
    }

    function _isLiquidatable(address user) internal view returns (bool) {
        uint256 collateralValue = getCollateralValue(user);
        uint256 debt = userBorrows[user];
        return (debt > 0 && debt * 100 > collateralValue * LIQUIDATION_THRESHOLD);
    }
    
    function sellWETHForUSDT(uint256 wethAmount) internal returns (uint256 usdtReceived) {
        if (wethAmount == 0) return 0;
        
        // Approve router to spend WETH
        IERC20(WETH).approve(UNISWAP_V3_ROUTER, wethAmount);
        
        // Market sell WETH for USDT
        ExactInputSingleParams memory params = ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDT,
            fee: 500, // 0.05%
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: wethAmount,
            amountOutMinimum: 0, // Accept any amount for liquidation
            sqrtPriceLimitX96: 0
        });
        
        try IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params) returns (uint256 amountOut) {
            return amountOut;
        } catch {
            // If swap fails, return 0
            return 0;
        }
    }
    
    function getNFTCount(address user) external view returns (uint256) {
        return userNFT[user] != 0 ? 1 : 0;
    }
    
    // For testing - mint some USDT (admin only in production)
    function mintTestUSDT(uint256 amount) public {
        userDeposits[msg.sender][USDT] += amount;
    }
    
    // For testing - wrap ETH to WETH (simplified)
    function wrapETH() public payable {
        require(msg.value > 0, "Send ETH");
        userDeposits[msg.sender][WETH] += msg.value;
    }
    
    // View functions for frontend
    function getMaxBorrowAmount(address user) external view returns (uint256) {
        uint256 collateralValue = getCollateralValue(user);
        uint256 currentDebt = userBorrows[user];
        uint256 maxDebt = (collateralValue * MAX_LTV) / 100;
        return maxDebt > currentDebt ? maxDebt - currentDebt : 0;
    }
    
    function getHealthFactor(address user) external view returns (uint256) {
        uint256 debt = userBorrows[user];
        if (debt == 0) return type(uint256).max; // Infinite health factor
        uint256 collateralValue = getCollateralValue(user);
        return (collateralValue * LIQUIDATION_THRESHOLD) / (debt * 100);
    }
} 