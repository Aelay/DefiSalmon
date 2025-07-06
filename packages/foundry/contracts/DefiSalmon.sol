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
    
    mapping(address => mapping(address => uint256)) public userDeposits; // user -> token -> amount
    mapping(address => uint256) public userNFT; // Only one NFT per user
    mapping(uint256 => address) public nftOwner;
    mapping(address => uint256) public userBorrows; // user -> total debt in USD
    
    function deposit(string memory token, uint256 amount) external {
        if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("weth"))) {
            IERC20(WETH).transferFrom(msg.sender, address(this), amount * 1e18);
            userDeposits[msg.sender][WETH] += amount * 1e18;
        } else if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("usdt"))) {
            IERC20(USDT).transferFrom(msg.sender, address(this), amount * 1e6);
            userDeposits[msg.sender][USDT] += amount * 1e6;
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
        userDeposits[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }
    
    function borrow(uint256 amount) external {
        require(getCollateralValue(msg.sender) > 0, "No collateral");
        userBorrows[msg.sender] += amount;
    }
    
    function getCollateralValue(address user) public view returns (uint256) {
        uint256 wethValue = (userDeposits[user][WETH] * getETHPrice()) / 1e8;
        uint256 usdtValue = userDeposits[user][USDT] / 1e6;
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
    
    function getNFTValue(uint256 tokenId) public view returns (uint256) {
        (,, address token0, address token1,, int24 tickLower, int24 tickUpper, uint128 liquidity,,, uint128 tokensOwed0, uint128 tokensOwed1) = 
            INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);
        
        uint256 currentTick = getCurrentTick();
        (uint256 amount0, uint256 amount1) = getTokenAmounts(liquidity, tickLower, tickUpper, currentTick);
        
        uint256 ethPrice = getETHPrice();
        uint256 totalValue = (amount0 + tokensOwed0) * ethPrice / 1e8 + (amount1 + tokensOwed1) / 1e6;
        
        return totalValue;
    }
    
    function getTokenAmounts(uint128 liquidity, int24 tickLower, int24 tickUpper, uint256 currentTick) internal pure returns (uint256 amount0, uint256 amount1) {
        if (currentTick < uint256(int256(tickLower))) {
            // Price below range: 100% token0
            amount0 = uint256(liquidity) * (getSqrtRatioAtTick(tickUpper) - getSqrtRatioAtTick(tickLower)) / (getSqrtRatioAtTick(tickUpper) * getSqrtRatioAtTick(tickLower));
            amount1 = 0;
        } else if (currentTick >= uint256(int256(tickUpper))) {
            // Price above range: 100% token1
            amount0 = 0;
            amount1 = uint256(liquidity) * (getSqrtRatioAtTick(tickUpper) - getSqrtRatioAtTick(tickLower));
        } else {
            // Price in range: mix of both tokens
            uint256 sqrtPriceX96 = getSqrtRatioAtTick(int24(int256(currentTick)));
            amount0 = uint256(liquidity) * (getSqrtRatioAtTick(tickUpper) - sqrtPriceX96) / (sqrtPriceX96 * getSqrtRatioAtTick(tickUpper));
            amount1 = uint256(liquidity) * (sqrtPriceX96 - getSqrtRatioAtTick(tickLower));
        }
    }
    
    function getCurrentTick() internal view returns (uint256) {
        // Simplified: convert current ETH price to tick
        uint256 ethPrice = getETHPrice();
        return uint256(int256(log2(ethPrice * 1e12))); // Rough approximation
    }
    
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint256) {
        // Simplified sqrt ratio calculation using integer math
        // For now, return a basic calculation - in production you'd use proper Uniswap math
        if (tick >= 0) {
            return uint256(1 << 96) + (uint256(int256(tick)) * uint256(1 << 96)) / 10000;
        } else {
            return uint256(1 << 96) - (uint256(int256(-tick)) * uint256(1 << 96)) / 10000;
        }
    }
    
    function log2(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        while (x > 1) {
            x >>= 1;
            result++;
        }
        return result;
    }
    
    function getETHPrice() public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(ETH_USD_FEED).latestRoundData();
        return uint256(price);
    }
    
    function repay(uint256 amount) external {
        userBorrows[msg.sender] -= amount;
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

    // --- Liquidation Step 2: Sell Collateral and Repay Debt ---
    function sellCollateral(address user) external returns (uint256 proceeds) {
        require(userNFT[user] == 0, "NFT must be closed first");
        require(_isLiquidatable(user), "Not liquidatable");
        // 1. Calculate total collateral and debt
        uint256 wethBalance = userDeposits[user][WETH];
        uint256 usdtBalance = userDeposits[user][USDT];
        uint256 debt = userBorrows[user];
        // 2. If there's debt, sell WETH to get USDT to repay it
        if (debt > 0 && wethBalance > 0) {
            uint256 wethToSell = wethBalance;
            uint256 usdtReceived = sellWETHForUSDT(wethToSell);
            userDeposits[user][WETH] = 0;
            userDeposits[user][USDT] += usdtReceived;
            usdtBalance = userDeposits[user][USDT];
        }
        // 3. Repay debt from USDT balance, send excess to liquidator
        if (debt > 0) {
            if (usdtBalance >= debt) {
                proceeds = usdtBalance - debt;
                userDeposits[user][USDT] = 0;
            } else {
                proceeds = 0;
                userDeposits[user][USDT] = 0;
            }
        } else {
            proceeds = (wethBalance * getETHPrice()) / 1e8 + (usdtBalance / 1e6);
            userDeposits[user][WETH] = 0;
            userDeposits[user][USDT] = 0;
        }
        userBorrows[user] = 0;
        return proceeds;
    }

    function _isLiquidatable(address user) internal view returns (bool) {
        uint256 collateralValue = getCollateralValue(user);
        uint256 debt = userBorrows[user];
        return (debt > 0 && debt * 100 > collateralValue * 80);
    }
    
    function sellWETHForUSDT(uint256 wethAmount) internal returns (uint256 usdtReceived) {
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
        
        usdtReceived = IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(params);
        return usdtReceived;
    }
    

    
    function getNFTCount(address user) external view returns (uint256) {
        return userNFT[user] != 0 ? 1 : 0;
    }
    
    // For testing - mint some USDT
    function mintTestUSDT(uint256 amount) public {
        userDeposits[msg.sender][USDT] += amount;
    }
    
    // For testing - wrap ETH to WETH
    function wrapETH() public payable {
        require(msg.value > 0, "Send ETH");
        userDeposits[msg.sender][WETH] += msg.value;
    }
} 