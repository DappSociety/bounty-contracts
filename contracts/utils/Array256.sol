pragma solidity ^0.4.19;

/**
 * @title Array256 Library
 *
 * Helper functions for working with uint256[] arrays.
 */
library Array256 {

  /**
   * @dev Delete a row by swapping the last element into its
   * place and decrementing an external pointer.
   * @param self Storage array containing uint256 type variables
   * @param index The row index to delete
   * @param pointer Pointer to the last true row
   * @return The new array pointer
   */
  function deleteRow(
    uint256[] storage self, uint256 index, uint256 pointer
  ) public returns (uint256) {
    if (index < pointer - 1) { self[index] = self[pointer - 1]; } // Move last row into deleting row
    self[pointer - 1] = 0; // Zero out the last row (not absolutely necessary)
    return pointer - 1; // Decrement the pointer
  }

  /**
   * @dev Add a value at the pointer index and increment the pointer.
   * @param self Storage array containing uint256 type variables
   * @param value The value to add to the array
   * @param pointer Pointer to the last true row
   * @return The new array pointer
   */
  function addRow(
    uint256[] storage self, uint256 value, uint256 pointer
  ) public returns (uint256) {
    // Add new array element
    if (pointer == self.length) { self.push(value); }
    // Add into next empty slot
    else { self[pointer] = value; }
    // Increment the pointer
    return pointer + 1;
  }
}
