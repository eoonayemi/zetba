// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin's Strings library for additional functionalities
import "@openzeppelin/contracts/utils/Strings.sol";

library S {
    using Strings for uint256; // Use the Strings utility for uint256 type

    /// @dev Concatenates three values: a string, a number, and another string.
    /// @param first The first string parameter.
    /// @param number The number to convert to a string.
    /// @param last The last string parameter.
    /// @return result A concatenated string of the three parameters.
    function concatenateAll(
        string memory first,
        uint256 number,
        string memory last
    ) internal pure returns (string memory) {
        // Use abi.encodePacked to concatenate the strings and number
        return string(abi.encodePacked(first, " ", number.toString(), " ", last));
    }
}
