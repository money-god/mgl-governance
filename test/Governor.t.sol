// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../src/Governor.sol";
import {DSDelegateToken} from "./mock/DSDelegateToken.sol";
import {DSPause, DSAuthority} from "./mock/DSPause.sol";

contract GovActions {
    function setOwner(address target, address owner) public virtual {
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

    uint256 public constant VOTING_DELAY = 2 days / 12; // convert to blocks
    uint256 public constant VOTING_PERIOD = 7 days / 12; // convert to blocks
    uint256 public constant PROPOSAL_THRESHOLD = 20000 ether;
    uint256 public constant PAUSE_DELAY = 1 days;

    // proposal to be used througout tests
    address[] public targets;
    bytes[] public calldatas;
    uint256 public proposalId;

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

        // setting up proposal to be used, it transfers ownership back to address(this)
        targets.push(govActions);
        calldatas.push(
            abi.encodeWithSelector(
                GovActions.setOwner.selector,
                address(pause),
                address(this)
            )
        );
        proposalId = governor.hashProposal(
            targets,
            new uint[](1),
            calldatas,
            keccak256(bytes("test proposal"))
        );
    }

    function _getExtCodeHash(address usr) internal view returns (bytes32 ch) {
        assembly {
            ch := extcodehash(usr)
        }
    }

    function testConstructor() public {
        assertEq(address(governor.token()), address(token));
        assertEq(governor.name(), "TaiGovernor");
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(address(governor.timelock()), address(pause));
    }

    function testPropose() public {
        token.mint(address(this), 20000 ether);
        token.delegate(address(this));
        vm.roll(block.number + 1);

        governor.propose(targets, new uint[](1), calldatas, "test proposal");

        assertEq(uint(governor.state(proposalId)), 0); // pending
        assertEq(
            uint(governor.proposalSnapshot(proposalId)),
            block.number + VOTING_DELAY
        );
        assertEq(
            uint(governor.proposalDeadline(proposalId)),
            block.number + VOTING_DELAY + VOTING_PERIOD
        );
        assertEq(governor.proposalProposer(proposalId), address(this));
    }

    function testProposalBelowThreshold() public {
        vm.expectRevert("Governor: proposer votes below proposal threshold");
        governor.propose(targets, new uint[](1), calldatas, "test proposal");
    }

    function testProposalInvalidData() public {
        token.mint(address(this), 20000 ether);
        token.delegate(address(this));
        vm.roll(block.number + 1);

        vm.expectRevert("Governor: invalid proposal length");
        governor.propose(targets, new uint[](0), calldatas, "test proposal");

        vm.expectRevert("Governor: invalid proposal length");
        governor.propose(
            targets,
            new uint[](1),
            new bytes[](0),
            "test proposal"
        );

        vm.expectRevert("Governor: empty proposal");
        governor.propose(
            new address[](0),
            new uint[](0),
            new bytes[](0),
            "test proposal"
        );

        // create a valid proposal
        governor.propose(targets, new uint[](1), calldatas, "test proposal");
        vm.expectRevert("Governor: proposal already exists");
        governor.propose(targets, new uint[](1), calldatas, "test proposal");
    }

    function testPassProposal() public {
        address alice = address(0x123);
        token.mint(alice, 10001 ether);
        vm.prank(alice);
        token.delegate(alice);

        testPropose();
        assertEq(uint(governor.state(proposalId)), 0); // pending

        // try to vote before it starts
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, 1); // support

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint(governor.state(proposalId)), 1); // active

        governor.castVote(proposalId, 1); // support

        vm.prank(alice);
        governor.castVote(proposalId, 1); // support

        vm.roll(block.number + VOTING_PERIOD);
        assertEq(uint(governor.state(proposalId)), 4); // succeeded

        // try to execute without queueing
        vm.expectRevert("GovernorTimelockCompound: proposal not yet queued");
        governor.execute(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );

        governor.queue(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
        assertEq(uint(governor.state(proposalId)), 5); // queued

        vm.warp(block.timestamp + PAUSE_DELAY);
        governor.execute(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
        assertEq(uint(governor.state(proposalId)), 7); // executed
        assertEq(pause.owner(), address(this));
    }

    function testDefeatProposal() public {
        address alice = address(0x123);
        token.mint(alice, 10001 ether);
        vm.prank(alice);
        token.delegate(alice);

        testPropose();
        assertEq(uint(governor.state(proposalId)), 0); // pending

        // try to vote before it starts
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, 1); // support

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint(governor.state(proposalId)), 1); // active

        governor.castVote(proposalId, 1); // support

        vm.prank(alice);
        governor.castVote(proposalId, 0); // against

        vm.roll(block.number + VOTING_PERIOD);
        assertEq(uint(governor.state(proposalId)), 3); // defeated

        // try to execute
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );

        // try to queue
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
    }

    function testCancelProposal() public {
        testPropose();
        assertEq(uint(governor.state(proposalId)), 0); // pending

        governor.cancel(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
        assertEq(uint(governor.state(proposalId)), 2); // cancelled

        // try voting
        vm.expectRevert("Governor: vote not currently active");
        governor.castVote(proposalId, 1); // support

        // try to execute
        vm.expectRevert("Governor: proposal not successful");
        governor.execute(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );

        // try to queue
        vm.expectRevert("Governor: proposal not successful");
        governor.queue(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
    }

    function testCancelProposalInvalid() public {
        testPropose();
        assertEq(uint(governor.state(proposalId)), 0); // pending

        vm.expectRevert("Governor: only proposer can cancel");
        vm.prank(address(0x1));
        governor.cancel(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
        assertEq(uint(governor.state(proposalId)), 0); // pending

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint(governor.state(proposalId)), 1); // active

        vm.expectRevert("Governor: too late to cancel");
        vm.prank(address(0x1));
        governor.cancel(
            targets,
            new uint[](1),
            calldatas,
            keccak256("test proposal")
        );
        assertEq(uint(governor.state(proposalId)), 1); // active
    }
}
