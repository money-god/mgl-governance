// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/Vetoer.sol";
import {DSDelegateToken} from "./mock/DSDelegateToken.sol";
import {DSPause, DSAuthority} from "./mock/DSPause.sol";

contract MockAuthority {
    mapping(address => bool) public authed;

    function setAuthed(address src, bool isAuthed) external {
        authed[src] = isAuthed;
    }

    function canCall(
        address src,
        address,
        bytes4
    ) external view returns (bool) {
        return authed[src];
    }
}

contract TaiVetoerTest is Test {
    TaiVetoer public vetoer;
    DSDelegateToken public token;
    MockAuthority public pauseAuthority;
    DSPause public pause;

    uint256 public constant PAUSE_DELAY = 1 days;

    function setUp() public {
        vm.roll(1e6);

        pauseAuthority = new MockAuthority();
        pause = new DSPause(
            PAUSE_DELAY,
            address(this),
            DSAuthority(address(pauseAuthority))
        );
        token = new DSDelegateToken("TAI", "TAI");

        vetoer = new TaiVetoer(
            ERC20VotesComp(address(token)),
            IDSPause(address(pause)),
            800 // 80%
        );

        pauseAuthority.setAuthed(address(vetoer), true);
    }

    function _getExtCodeHash(address usr) internal view returns (bytes32 ch) {
        assembly {
            ch := extcodehash(usr)
        }
    }

    function testConstructor() external {
        assertEq(address(vetoer.token()), address(token));
        assertEq(address(vetoer.pause()), address(pause));
        assertEq(vetoer.supplyPercentage(), 800);
    }

    function testVetoThreshold() external {
        token.mint(address(0x0dd), 1000000 ether);
        assertEq(vetoer.vetoThreshold(), 800000 ether);
    }

    mapping(address => bool) _seen;

    /**
     * forge-config: default.fuzz.runs = 10000
     */
    function testProposalCollision(
        address[] memory usr,
        bytes[] memory parameters,
        uint eta
    ) public {
        if (usr.length != parameters.length) return;
        address addr = vetoer.getProposalAddress(usr, parameters, eta);
        assertFalse(_seen[addr]);
        _seen[addr] = true;
    }

    function testVetoProposal() public {
        // proposal data
        address usr = address(0x0dd);
        bytes memory parameters = abi.encodeWithSignature("proposal()");
        uint eta = block.timestamp + pause.delay();

        // schedule proposal
        pause.scheduleTransaction(usr, _getExtCodeHash(usr), parameters, eta);
        assertEq(pause.currentlyScheduledTransactions(), 1);

        // fetch the address of the proposal
        address[] memory usrs = new address[](1);
        usrs[0] = usr;

        bytes[] memory params = new bytes[](1);
        params[0] = parameters;

        address proposalAddress = vetoer.getProposalAddress(usrs, params, eta);

        // mint tokens
        token.mint(address(this), 1000000 ether);

        // delegate to proposal
        token.delegate(proposalAddress);
        vm.roll(block.number + 5);

        // veto
        vetoer.vetoProposal(usrs, params, eta);
        assertEq(pause.currentlyScheduledTransactions(), 0);
    }

    function testVetoProposalInsuficientVotes() public {
        // proposal data
        address usr = address(0x0dd);
        bytes memory parameters = abi.encodeWithSignature("proposal()");
        uint eta = block.timestamp + pause.delay();

        // schedule proposal
        pause.scheduleTransaction(usr, _getExtCodeHash(usr), parameters, eta);
        assertEq(pause.currentlyScheduledTransactions(), 1);

        // fetch the address of the proposal
        address[] memory usrs = new address[](1);
        usrs[0] = usr;

        bytes[] memory params = new bytes[](1);
        params[0] = parameters;

        address proposalAddress = vetoer.getProposalAddress(usrs, params, eta);

        // mint tokens
        token.mint(address(this), 79999999);
        token.mint(address(0x0dd), 21111111);

        // delegate to proposal
        token.delegate(proposalAddress);
        vm.roll(block.number + 5);

        // veto
        vm.expectRevert("insuficient support for vetoing this proposal");
        vetoer.vetoProposal(usrs, params, eta);
        assertEq(pause.currentlyScheduledTransactions(), 1);
    }

    function testVetoProposalBeforeBlock() public {
        // proposal data
        address usr = address(0x0dd);
        bytes memory parameters = abi.encodeWithSignature("proposal()");
        uint eta = block.timestamp + pause.delay();

        // schedule proposal
        pause.scheduleTransaction(usr, _getExtCodeHash(usr), parameters, eta);
        assertEq(pause.currentlyScheduledTransactions(), 1);

        // fetch the address of the proposal
        address[] memory usrs = new address[](1);
        usrs[0] = usr;

        bytes[] memory params = new bytes[](1);
        params[0] = parameters;

        address proposalAddress = vetoer.getProposalAddress(usrs, params, eta);

        // mint tokens
        token.mint(address(this), 1000000 ether);

        // delegate to proposal
        token.delegate(proposalAddress);
        vm.roll(block.number + 4);

        // veto
        vm.expectRevert("insuficient support for vetoing this proposal");
        vetoer.vetoProposal(usrs, params, eta);
        assertEq(pause.currentlyScheduledTransactions(), 1);
    }

    /**
     * forge-config: default.fuzz.runs = 10000
     */
    function testVetoProposalFuzz(
        address[] memory usrs,
        bytes[] memory params,
        uint eta
    ) public {
        if (params.length != usrs.length) return;
        if (params.length > 9) return; // pause proposal limit
        if (eta < block.timestamp + pause.delay()) return;

        // schedule proposal
        for (uint i; i < usrs.length; i++) {
            try
                pause.scheduleTransaction(
                    usrs[i],
                    _getExtCodeHash(usrs[i]),
                    params[i],
                    eta
                )
            {} catch {
                return;
            }
        }

        assertEq(pause.currentlyScheduledTransactions(), usrs.length);

        address proposalAddress = vetoer.getProposalAddress(usrs, params, eta);

        // mint tokens
        token.mint(address(this), 1000000 ether);

        // delegate to proposal
        token.delegate(proposalAddress);
        vm.roll(block.number + 5);

        // veto
        vetoer.vetoProposal(usrs, params, eta);
        assertEq(pause.currentlyScheduledTransactions(), 0);
    }
}
