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
        address[] s_shareholders;
        // Position is the index of the value in the `s_shareholders` array plus 1.
        // Position 0 is used to mean a value is not in the set.
        mapping(address shareholder => uint256 position) s_positionOf;
        // Amount of shares a given shareholder owns
        mapping(address shareholder => uint256 shares) s_sharesOf;
        // Amount of shares a given shareholder has staked
        mapping(address shareholder => uint256 stakedShares) s_stakedSharesOf;
        // Amount of dividends a given shareholder has withdrawn
        mapping(address shareholder => uint256 withdrawnDividends) s_withdrawnDividendsOf;
        // Amount of RayFi a given shareholder has reinvested
        mapping(address shareholder => uint256 reinvestedRayFi) s_reinvestedRayFiOf;
    }

    /**
     * @dev Add a value to a set. O(1).
     */
    function add(ShareholderSet storage set, address value, uint256 shares) internal {
        if (!contains(set, value)) {
            set.s_shareholders.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set.s_positionOf[value] = set.s_shareholders.length;
        }
        set.s_sharesOf[value] = shares;
    }

    /**
     * @dev Set the amount of staked shares for a shareholder in the set. O(1).
     */
    function addStakedShares(ShareholderSet storage set, address value, uint256 stakedShares) internal {
        set.s_stakedSharesOf[value] = stakedShares;
    }

    /**
     * @dev Set the amount of dividends withdrawn for a shareholder in the set. O(1).
     */
    function addWithdrawnDividends(ShareholderSet storage set, address value, uint256 withdrawnDividends) internal {
        set.s_withdrawnDividendsOf[value] = withdrawnDividends;
    }

    /**
     * @dev Set the amount of RayFi reinvested for a shareholder in the set. O(1).
     */
    function addReinvestedRayFi(ShareholderSet storage set, address value, uint256 reinvestedRayFi) internal {
        set.s_reinvestedRayFiOf[value] = reinvestedRayFi;
    }

    /**
     * @dev Removes a value from a set. O(1).
     */
    function remove(ShareholderSet storage set, address value) internal {
        // We cache the value's position to prevent multiple reads from the same storage slot
        uint256 position = set.s_positionOf[value];

        if (position != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the s_shareholders array in O(1), we swap the element to delete
            // with the last one in the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 valueIndex = position - 1;
            uint256 lastIndex = set.s_shareholders.length - 1;

            if (valueIndex != lastIndex) {
                address lastValue = set.s_shareholders[lastIndex];

                // Move the lastValue to the index where the value to delete is
                set.s_shareholders[valueIndex] = lastValue;
                // Update the tracked position of the lastValue (that was just moved)
                set.s_positionOf[lastValue] = position;
            }

            // Delete the slot where the moved value was stored
            set.s_shareholders.pop();

            // Delete the tracked index for the deleted slot
            delete set.s_positionOf[value];
            // Delete the share data for the deleted slot
            delete set.s_sharesOf[value];
            // Delete the staked share data for the deleted slot
            delete set.s_stakedSharesOf[value];
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(ShareholderSet storage set, address value) internal view returns (bool) {
        return set.s_positionOf[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(ShareholderSet storage set) internal view returns (uint256) {
        return set.s_shareholders.length;
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
        return set.s_shareholders[index];
    }

    /**
     * @dev Returns the amount of shares for a shareholder in the set. O(1).
     */
    function sharesOf(ShareholderSet storage set, address shareholder) internal view returns (uint256) {
        return set.s_sharesOf[shareholder];
    }

    /**
     * @dev Returns the amount of staked shares for a shareholder in the set. O(1).
     */
    function stakedSharesOf(ShareholderSet storage set, address shareholder) internal view returns (uint256) {
        return set.s_stakedSharesOf[shareholder];
    }

    /**
     * @dev Returns the amount of dividends withdrawn for a shareholder in the set. O(1).
     */
    function withdrawnDividendsOf(ShareholderSet storage set, address shareholder) internal view returns (uint256) {
        return set.s_withdrawnDividendsOf[shareholder];
    }

    /**
     * @dev Returns the amount of RayFi reinvested for a shareholder in the set. O(1).
     */
    function reinvestedRayFiOf(ShareholderSet storage set, address shareholder) internal view returns (uint256) {
        return set.s_reinvestedRayFiOf[shareholder];
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
        return set.s_shareholders;
    }
}
