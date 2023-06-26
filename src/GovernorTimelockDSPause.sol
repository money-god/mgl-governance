// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/governance/Governor.sol";
import "openzeppelin-contracts/contracts/governance/extensions/IGovernorTimelock.sol";
import "./IDSPause.sol";

/**
 * @dev Extension of {Governor} that binds the execution process to an instance of {DSPause}. This adds a
 * delay, enforced by the {DSPause} to all successful proposal (in addition to the voting duration). The
 * {Governor} needs the proposer (and ideally the executor) roles for the {Governor} to work properly.
 *
 * Using this model means the proposal will be operated by the {DSPause} and not by the {Governor}. Thus,
 * the assets and permissions must be attached to the {DSPause.proxy()}. Any asset sent to the {Governor} will be
 * inaccessible.
 *
 * DSPause uses delegatecalls unlike the OZ and Compound timelocks, pack the proposals accordingly or they will fail.
 *
 * WARNING: Setting up the DSPause to have additional proposers besides the governor is very risky, as it
 * grants them powers that they must be trusted or known not to use: 1) {onlyGovernance} functions like {relay} are
 * available to them through the timelock, and 2) approved governance proposals can be blocked by them, effectively
 * executing a Denial of Service attack.
 *
 */
abstract contract GovernorTimelockDSPause is IGovernorTimelock, Governor {
    IDSPause private _pause;

    mapping(uint256 => uint64) private _proposalTimelocks;

    /**
     * @dev Emitted when the timelock controller used for proposal execution is modified.
     */
    event TimelockChange(address oldTimelock, address newTimelock);

    /**
     * @dev Set the timelock.
     */
    constructor(IDSPause timelockAddress) {
        _updateTimelock(timelockAddress);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, Governor) returns (bool) {
        return
            interfaceId == type(IGovernorTimelock).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Overridden version of the {Governor-state} function with added support for the `Queued` and `Expired` state.
     */
    function state(
        uint256 proposalId
    )
        public
        view
        virtual
        override(IGovernor, Governor)
        returns (ProposalState)
    {
        ProposalState currentState = super.state(proposalId);

        if (currentState != ProposalState.Succeeded) {
            return currentState;
        }

        uint256 eta = proposalEta(proposalId);
        if (eta == 0) {
            return currentState;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @dev Public accessor to check the address of the timelock
     */
    function timelock() public view virtual override returns (address) {
        return address(_pause);
    }

    /**
     * @dev Public accessor to check the eta of a queued proposal
     */
    function proposalEta(
        uint256 proposalId
    ) public view virtual override returns (uint256) {
        return _proposalTimelocks[proposalId];
    }

    /**
     * @dev Function to queue a proposal to the timelock.
     */
    function queue(
        address[] memory targets,
        uint256[] memory /* values */, // unused
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override returns (uint256) {
        uint256 proposalId = hashProposal(
            targets,
            new uint256[](targets.length),
            calldatas,
            descriptionHash
        ); // update

        require(
            state(proposalId) == ProposalState.Succeeded,
            "Governor: proposal not successful"
        );

        uint256 eta = block.timestamp + _pause.delay();
        _proposalTimelocks[proposalId] = SafeCast.toUint64(eta);

        for (uint256 i = 0; i < targets.length; ++i) {
            _pause.scheduleTransaction(
                targets[i],
                _getExtCodeHash(targets[i]),
                calldatas[i],
                eta
            );
        }

        emit ProposalQueued(proposalId, eta);

        return proposalId;
    }

    /**
     * @dev Overridden execute function that run the already queued proposal through the timelock.
     * @dev If pause call fails it will mark the proposal as executed anyway (this can hapen due to logic error on proposal or a proposal that was already executed directly on pause).
     */
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory /*values*/,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual override {
        uint256 eta = proposalEta(proposalId);
        require(eta > 0, "GovernorTimelockCompound: proposal not yet queued");
        for (uint256 i = 0; i < targets.length; ++i) {
            try
                _pause.executeTransaction(
                    targets[i],
                    _getExtCodeHash(targets[i]),
                    calldatas[i],
                    eta
                )
            {} catch {}
        }
    }

    /**
     * @dev Overridden version of the {Governor-_cancel} function to cancel the scheduled proposal if it as already
     * been queued.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory /*values*/,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override returns (uint256) {
        uint256 proposalId = super._cancel(
            targets,
            new uint256[](targets.length),
            calldatas,
            descriptionHash
        );

        uint256 eta = proposalEta(proposalId);
        if (eta > 0) {
            // update state first
            delete _proposalTimelocks[proposalId];
            // do external call later
            for (uint256 i = 0; i < targets.length; ++i) {
                _pause.abandonTransaction(
                    targets[i],
                    _getExtCodeHash(targets[i]),
                    calldatas[i],
                    eta
                );
            }
        }

        return proposalId;
    }

    /**
     * @dev Address through which the governor executes action. In this case, the pause.proxy().
     */
    function _executor() internal view virtual override returns (address) {
        return _pause.proxy();
    }

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * For security reasons, the timelock must be handed over to another admin before setting up a new one. The two
     * operations (hand over the timelock) and do the update can be batched in a single proposal.
     *
     * Note that if the timelock admin has been handed over in a previous operation, we refuse updates made through the
     * timelock if admin of the timelock has already been accepted and the operation is executed outside the scope of
     * governance.

     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateTimelock(
        IDSPause newTimelock
    ) external virtual onlyGovernance {
        _updateTimelock(newTimelock);
    }

    function _updateTimelock(IDSPause newTimelock) private {
        emit TimelockChange(address(_pause), address(newTimelock));
        _pause = newTimelock;
    }

    /**
     * @dev Returns `extcodehash` for a given address.
     */
    function _getExtCodeHash(address usr) internal view returns (bytes32 ch) {
        assembly {
            ch := extcodehash(usr)
        }
    }
}
