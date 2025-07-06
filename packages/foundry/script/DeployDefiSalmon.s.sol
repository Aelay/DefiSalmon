// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/DefiSalmon.sol";

/**
 * @notice Deploy script for DefiSalmon contract
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployDefiSalmon.s.sol  # local anvil chain
 * yarn deploy --file DeployDefiSalmon.s.sol --network optimism # live network (requires keystore)
 */
contract DeployDefiSalmon is ScaffoldETHDeploy {
    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`:
     *      - "scaffold-eth-default": Uses Anvil's account #9 (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720), no password prompt
     *      - "scaffold-eth-custom": requires password used while creating keystore
     *
     * Note: Must use ScaffoldEthDeployerRunner modifier to:
     *      - Setup correct `deployer` account and fund it
     *      - Export contract addresses & ABIs to `nextjs` packages
     */
    function run() external ScaffoldEthDeployerRunner {
        // For now, using placeholder addresses for WETH and USDT
        // In a real deployment, these would be actual token addresses
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Mainnet USDT
        DefiSalmon defiSalmon = new DefiSalmon(weth, usdt);
        addDeployment("DefiSalmon", address(defiSalmon));
    }
}
