// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/governance/Governor.sol";
import "openzeppelin-contracts/contracts/governance/extensions/GovernorSettings.sol";
import "openzeppelin-contracts/contracts/governance/extensions/GovernorCountingSimple.sol";
import "openzeppelin-contracts/contracts/governance/extensions/GovernorVotesComp.sol";
import "./GovernorTimelockDSPause.sol";

contract TaiGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotesComp,
    GovernorTimelockDSPause
{
    address public immutable tokenEmitter;
    uint256 public quorumPercentage = 30; // default 30 == 3%
    uint256 public constant MIN_QUORUM_PERCENTAGE = 30;
    uint256 public constant MAX_QUORUM_PERCENTAGE = 50;

    event QuorumPercentageSet(uint256 oldPercentage, uint256 newPercentage);

    constructor(
        ERC20VotesComp _token,
        IDSPause _pause,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        address _tokenEmitter
    )
        Governor("TaiGovernor")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorVotesComp(_token)
        GovernorTimelockDSPause(_pause)
    {
        tokenEmitter = _tokenEmitter;
    }

    /**
     * @dev Update the quorum percentage. This operation can only be performed through a governance proposal.
     *
     * Emits a {QuotumPercentageSet} event.
     */
    function setQuorumPercentage(
        uint256 newPercentage
    ) public virtual onlyGovernance {
        _setQuorumPercentage(newPercentage);
    }

    function quorum(
        uint256 /*blockNumber*/
    ) public view override returns (uint256) {
        uint256 circulatingSupply = token.totalSupply() -
            token.balanceOf(tokenEmitter);
        return (circulatingSupply * quorumPercentage) / 1000;
    }

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function state(
        uint256 proposalId
    )
        public
        view
        override(Governor, GovernorTimelockDSPause)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockDSPause) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockDSPause) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockDSPause)
        returns (address)
    {
        return super._executor();
    }

    /**
     * @dev Internal setter for the quorum percentage.
     *
     * Emits a {QuorumPercentageSet} event.
     */
    function _setQuorumPercentage(uint256 newPercentage) internal virtual {
        require(
            newPercentage >= MIN_QUORUM_PERCENTAGE &&
                newPercentage <= MAX_QUORUM_PERCENTAGE,
            "Governor: invalid quorum"
        );
        emit QuorumPercentageSet(quorumPercentage, newPercentage);
        quorumPercentage = newPercentage;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(Governor, GovernorTimelockDSPause) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
