// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract DefiSalmon {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    mapping(address => mapping(address => uint256)) public deposits; // user -> token -> amount
    mapping(address => uint256[]) public userNFTs;
    mapping(uint256 => address) public nftOwner;
    mapping(address => uint256) public borrows;
    
    function deposit(string memory token, uint256 amount) external {
        if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("weth"))) {
            IERC20(WETH).transferFrom(msg.sender, address(this), amount * 1e18);
            deposits[msg.sender][WETH] += amount * 1e18;
        } else if (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked("usdt"))) {
            IERC20(USDT).transferFrom(msg.sender, address(this), amount * 1e6);
            deposits[msg.sender][USDT] += amount * 1e6;
        } else {
            revert("Use 'weth' or 'usdt'");
        }
    }
    
    function depositV3Pos(uint256 tokenId) external {
        IERC721(0xC36442b4a4522E871399CD717aBDD847Ab11FE88).transferFrom(msg.sender, address(this), tokenId);
        userNFTs[msg.sender].push(tokenId);
        nftOwner[tokenId] = msg.sender;
    }
    
    function withdraw(address token, uint256 amount) external {
        require(token == WETH || token == USDT, "Invalid token");
        require(deposits[msg.sender][token] >= amount, "Insufficient balance");
        deposits[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }
    
    function borrow(uint256 amount) external {
        require(getCollateralValue(msg.sender) > 0, "No collateral");
        borrows[msg.sender] += amount;
    }
    
    function getCollateralValue(address user) public view returns (uint256) {
        return deposits[user][WETH] + deposits[user][USDT] + (userNFTs[user].length * 1000); // Simple NFT value
    }
    
    function repay(uint256 amount) external {
        borrows[msg.sender] -= amount;
    }
    
    function getNFTCount(address user) external view returns (uint256) {
        return userNFTs[user].length;
    }
    
    // For testing - mint some USDT
    function mintTestUSDT(uint256 amount) public {
        deposits[msg.sender][USDT] += amount;
    }
    
    // For testing - wrap ETH to WETH
    function wrapETH() public payable {
        require(msg.value > 0, "Send ETH");
        deposits[msg.sender][WETH] += msg.value;
    }
} 