// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
        DefiSalmon defiSalmon = new DefiSalmon();
        addDeployment("DefiSalmon", address(defiSalmon));

        console.log("DefiSalmon deployed to:", address(defiSalmon));
        console.log("WETH address:", defiSalmon.WETH());
        console.log("USDT address:", defiSalmon.USDT());
        console.log("ETH/USD Feed:", defiSalmon.ETH_USD_FEED());
        console.log("Position Manager:", defiSalmon.POSITION_MANAGER());
        console.log("Uniswap Router:", defiSalmon.UNISWAP_V3_ROUTER());
        console.log("WETH/USDT Pool:", defiSalmon.WETH_USDT_POOL());
    }
}
