//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] _keys;
        mapping(address => uint256) _values;
        mapping(address => uint256) _indexOf;
        mapping(address => bool) _inserted;
    }

    function get(Map storage map, address key) internal view returns (uint256) {
        return map._values[key];
    }

    function getIndexOfKey(Map storage map, address key) internal view returns (int256) {
        if (!map._inserted[key]) {
            return -1;
        }
        return int256(map._indexOf[key]);
    }

    function getKeyAtIndex(Map storage map, uint256 index) internal view returns (address) {
        return map._keys[index];
    }

    function size(Map storage map) internal view returns (uint256) {
        return map._keys.length;
    }

    function set(Map storage map, address key, uint256 val) internal {
        if (map._inserted[key]) {
            map._values[key] = val;
        } else {
            map._inserted[key] = true;
            map._values[key] = val;
            map._indexOf[key] = map._keys.length;
            map._keys.push(key);
        }
    }

    function remove(Map storage map, address key) internal {
        if (!map._inserted[key]) {
            return;
        }

        delete map._inserted[key];
        delete map._values[key];

        uint256 index = map._indexOf[key];
        uint256 lastIndex = map._keys.length - 1;
        address lastKey = map._keys[lastIndex];

        map._indexOf[lastKey] = index;
        delete map._indexOf[key];

        map._keys[index] = lastKey;
        map._keys.pop();
    }

    function keys(Map storage map) internal view returns (address[] memory) {
        return map._keys;
    }
}
