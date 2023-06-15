// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "openzeppelin-contracts/contracts/governance/Governor.sol";
import "openzeppelin-contracts/contracts/governance/extensions/GovernorVotesComp.sol";
import "openzeppelin-contracts/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import "openzeppelin-contracts/contracts/governance/extensions/GovernorSettings.sol";
import "./GovernorTimelockDSPause.sol";

contract TaiGovernor is
    Governor,
    GovernorSettings,
    GovernorCompatibilityBravo,
    GovernorVotesComp,
    GovernorTimelockDSPause
{
    constructor(
        ERC20VotesComp _token,
        IDSPause _pause,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold
    )
        Governor("TaiGovernor")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorVotesComp(_token)
        GovernorTimelockDSPause(_pause)
    {}

    function quorum(
        uint256 /*blockNumber*/
    ) public pure override returns (uint256) {
        return 30000e18;
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
        override(Governor, IGovernor, GovernorTimelockDSPause)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    )
        public
        override(Governor, GovernorCompatibilityBravo, IGovernor)
        returns (uint256)
    {
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

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(Governor, IERC165, GovernorTimelockDSPause)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        public
        override(Governor, IGovernor, GovernorCompatibilityBravo)
        returns (uint256)
    {
        return super.cancel(targets, values, calldatas, descriptionHash);
    }
}
