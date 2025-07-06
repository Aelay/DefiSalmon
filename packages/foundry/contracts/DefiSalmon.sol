// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
}

contract DefiSalmon {
    mapping(address => mapping(address => uint)) public deposits;
    mapping(address => mapping(address => uint)) public borrows;
    address public immutable WETH;
    address public immutable USDT;
    
    // Simple price oracle (in practice, use Chainlink)
    uint public wethPrice = 2000e6; // $2000 in USDT (6 decimals)
    uint public liquidationThreshold = 8000; // 80% (8000/10000)
    uint public liquidationBonus = 500; // 5% bonus (500/10000)

    constructor(address _weth, address _usdt) {
        WETH = _weth;
        USDT = _usdt;
    }

    function deposit(address asset, uint amount) external {
        require(asset == WETH || asset == USDT, "Invalid asset");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][asset] += amount;
    }

    function withdraw(address asset, uint amount) external {
        require(asset == WETH || asset == USDT, "Invalid asset");
        require(deposits[msg.sender][asset] >= amount, "Not enough deposits");
        deposits[msg.sender][asset] -= amount;
        require(getHealthFactor(msg.sender) >= 1e18, "Health factor too low");
        IERC20(asset).transfer(msg.sender, amount);
    }

    function borrow(address asset, uint amount) external {
        require(asset == WETH || asset == USDT, "Invalid asset");
        require(IERC20(asset).transfer(msg.sender, amount), "Not enough liquidity");
        borrows[msg.sender][asset] += amount;
        require(getHealthFactor(msg.sender) >= 1e18, "Health factor too low");
    }

    function repay(address asset, uint amount) external {
        require(asset == WETH || asset == USDT, "Invalid asset");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        borrows[msg.sender][asset] -= amount;
    }

    function liquidate(address user, address asset) external {
        require(getHealthFactor(user) < 1e18, "User not liquidatable");
        uint borrowed = borrows[user][asset];
        require(borrowed > 0, "Nothing to liquidate");
        
        uint collateralValue = getCollateralValue(user);
        uint debtValue = getDebtValue(user);
        uint maxRepay = (debtValue * liquidationThreshold) / 10000;
        
        uint repayAmount = borrowed;
        if (getAssetValue(asset, borrowed) > maxRepay) {
            repayAmount = (maxRepay * 1e18) / getAssetPrice(asset);
        }
        
        IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);
        borrows[user][asset] -= repayAmount;
        
        uint bonus = (repayAmount * liquidationBonus) / 10000;
        uint liquidatorReward = repayAmount + bonus;
        
        // Give liquidator WETH as reward (simplified)
        uint rewardAmount = (liquidatorReward * getAssetPrice(asset)) / wethPrice;
        IERC20(WETH).transfer(msg.sender, rewardAmount);
    }

    function getHealthFactor(address user) public view returns (uint) {
        uint collateralValue = getCollateralValue(user);
        uint debtValue = getDebtValue(user);
        if (debtValue == 0) return type(uint).max;
        return (collateralValue * liquidationThreshold) / (debtValue * 10000);
    }

    function getCollateralValue(address user) internal view returns (uint) {
        return getAssetValue(WETH, deposits[user][WETH]) + 
               getAssetValue(USDT, deposits[user][USDT]);
    }

    function getDebtValue(address user) internal view returns (uint) {
        return getAssetValue(WETH, borrows[user][WETH]) + 
               getAssetValue(USDT, borrows[user][USDT]);
    }

    function getAssetValue(address asset, uint amount) internal view returns (uint) {
        return (amount * getAssetPrice(asset)) / 1e18;
    }

    function getAssetPrice(address asset) internal view returns (uint) {
        return asset == WETH ? wethPrice : 1e6; // USDT = $1
    }
} 