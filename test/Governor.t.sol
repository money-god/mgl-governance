// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/Governor.sol";
import {DSDelegateToken} from "./mock/DSDelegateToken.sol";
import {DSPause, DSAuthority} from "./mock/DSPause.sol";

contract GovActions {
    function setOwner(address target, address owner) external virtual {
        (bool success, ) = target.call(
            abi.encodeWithSelector(DSPause.setOwner.selector, owner)
        );
        require(success);
    }
}

contract GovernorTest is Test {
    TaiGovernor public governor;
    DSDelegateToken public token;
    DSPause public pause;
    address public govActions;

    uint256 public constant VOTING_DELAY = 2 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant PROPOSAL_THRESHOLD = 20000 ether;
    uint256 public constant PAUSE_DELAY = 1 days;

    function setUp() public {
        pause = new DSPause(
            PAUSE_DELAY,
            address(this),
            DSAuthority(address(0))
        );
        token = new DSDelegateToken("RATE", "RATE");
        govActions = address(new GovActions());

        governor = new TaiGovernor(
            ERC20VotesComp(address(token)),
            IDSPause(address(pause)),
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );

        // transfer pause ownership to governor
        pause.scheduleTransaction(
            govActions,
            _getExtCodeHash(govActions),
            abi.encodeWithSelector(
                GovActions.setOwner.selector,
                address(pause),
                address(governor)
            ),
            block.timestamp + pause.delay()
        );
        vm.warp(block.timestamp + pause.delay());
        pause.executeTransaction(
            govActions,
            _getExtCodeHash(govActions),
            abi.encodeWithSelector(
                GovActions.setOwner.selector,
                address(pause),
                address(governor)
            ),
            block.timestamp
        );

        assertEq(pause.owner(), address(governor));
    }

    function _getExtCodeHash(address usr) internal view returns (bytes32 ch) {
        assembly {
            ch := extcodehash(usr)
        }
    }

    function testConstructor() external {}
}
