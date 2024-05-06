// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title RayFiLibrary
 * @author 0xC4LL3
 * @notice This library was forked from OpenZeppelin Contracts v5.0.0 (utils/structs/EnumerableSet.sol)
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types, with additional shareholder data
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```solidity
 * contract Example {
 *     // Add the library methods
 *     using RayFiLibrary for RayFiLibrary.ShareholderSet;
 *
 *     // Declare a set state variable
 *     RayFiLibrary.ShareholderSet internal myShareholderSet;
 * }
 * ```
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean a ShareholderSet, you can either remove all elements one by one or create a fresh instance using an
 * array of ShareholderSet.
 * ====
 */
library RayFiLibrary {
    struct ShareholderSet {
        // Storage of shareholder addresses
        address[] _shareholders;
        // Position is the index of the value in the `_shareholders` array plus 1.
        // Position 0 is used to mean a value is not in the set.
        mapping(address shareholder => uint256 position) _positionOf;
        // Amount of shares a given shareholder owns
        mapping(address shareholder => uint256 shares) _sharesOf;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(ShareholderSet storage set, address value, uint256 shares) internal {
        if (!contains(set, value)) {
            set._shareholders.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._positionOf[value] = set._shareholders.length;
        }
        set._sharesOf[value] = shares;
    }

    /**
     * @dev Removes a value from a set. O(1).
     */
    function remove(ShareholderSet storage set, address value) internal {
        // We cache the value's position to prevent multiple reads from the same storage slot
        uint256 position = set._positionOf[value];

        if (position != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _shareholders array in O(1), we swap the element to delete
            // with the last one in the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 valueIndex = position - 1;
            uint256 lastIndex = set._shareholders.length - 1;

            if (valueIndex != lastIndex) {
                address lastValue = set._shareholders[lastIndex];

                // Move the lastValue to the index where the value to delete is
                set._shareholders[valueIndex] = lastValue;
                // Update the tracked position of the lastValue (that was just moved)
                set._positionOf[lastValue] = position;
            }

            // Delete the slot where the moved value was stored
            set._shareholders.pop();

            // Delete the tracked index for the deleted slot
            delete set._positionOf[value];
            // Delete the share data for the deleted slot
            delete set._sharesOf[value];
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(ShareholderSet storage set, address value) internal view returns (bool) {
        return set._positionOf[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(ShareholderSet storage set) internal view returns (uint256) {
        return set._shareholders.length;
    }

    /**
     * @dev Returns the address of the shareholder stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function shareholderAt(ShareholderSet storage set, uint256 index) internal view returns (address) {
        return set._shareholders[index];
    }

    /**
     * @dev Returns the amount of shares for a shareholder in the set. O(1).
     */
    function sharesOf(ShareholderSet storage set, address shareholder) internal view returns (uint256) {
        return set._sharesOf[shareholder];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function shareholders(ShareholderSet storage set) internal view returns (address[] memory) {
        return set._shareholders;
    }
}
