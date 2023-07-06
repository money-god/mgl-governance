// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./IDSPause.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20VotesComp.sol";

contract TaiVetoer {
    ERC20VotesComp public immutable token;
    IDSPause public immutable pause;
    uint256 public immutable supplyPercentage; // 1000 = 100%

    constructor(
        ERC20VotesComp _token,
        IDSPause _pause,
        uint256 _supplyPercentage
    ) {
        require(_supplyPercentage <= 1000, "invalid percentage");
        token = _token;
        pause = _pause;
        supplyPercentage = _supplyPercentage;
    }

    /**
     * @notice Vetoes a scheduled proposal that has enough support.
     * @notice Parameters are the same as the proposal being vetoed.
     * @notice Will only veto if the proposal address has enough support delegated to it.
     */
    function vetoProposal(
        address[] calldata usr,
        bytes[] calldata parameters,
        uint eta
    ) external {
        require(
            token.getPriorVotes(
                getProposalAddress(usr, parameters, eta),
                block.number - 5
            ) >= vetoThreshold(),
            "insuficient support for vetoing this proposal"
        );

        for (uint i; i < usr.length; i++)
            pause.abandonTransaction(
                usr[i],
                _getExtCodeHash(usr[i]),
                parameters[i],
                eta
            );
    }

    /**
     * @notice Returns current threshold for vetoing a proposal.
     */
    function vetoThreshold() public view returns (uint256) {
        return (token.totalSupply() * supplyPercentage) / 1000;
    }

    /**
     * @notice Returns an address for a given proposal.
     */
    function getProposalAddress(
        address[] memory usr,
        bytes[] memory parameters,
        uint eta
    ) public pure returns (address addr) {
        require(usr.length == parameters.length, "invalid data");
        bytes32 hash = keccak256(abi.encode(usr, parameters, eta));
        assembly {
            mstore(0, hash)
            addr := mload(0)
        }
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
