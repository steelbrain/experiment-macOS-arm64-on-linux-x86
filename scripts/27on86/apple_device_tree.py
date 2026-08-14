#!/usr/bin/env python3

"""Small helpers for editing the flattened Apple Device Tree format."""

import struct


PROPERTY_NAME_SIZE = 32
PROPERTY_HEADER_SIZE = PROPERTY_NAME_SIZE + 4
PROPERTY_LENGTH_MASK = 0x00FFFFFF


class DeviceTreeError(ValueError):
    """The flattened tree does not satisfy the expected wire format."""


def _aligned_size(size: int) -> int:
    return (size + 3) & ~3


def _node_at(tree: bytearray, offset: int, end: int):
    if offset + 8 > end:
        raise DeviceTreeError("truncated node header")

    property_count, child_count = struct.unpack_from("<II", tree, offset)
    cursor = offset + 8
    properties = {}
    for _ in range(property_count):
        if cursor + PROPERTY_HEADER_SIZE > end:
            raise DeviceTreeError("truncated property header")
        name_field = bytes(tree[cursor : cursor + PROPERTY_NAME_SIZE])
        name = name_field.split(b"\0", 1)[0].decode("ascii", errors="strict")
        raw_length = struct.unpack_from("<I", tree, cursor + PROPERTY_NAME_SIZE)[0]
        length = raw_length & PROPERTY_LENGTH_MASK
        value_offset = cursor + PROPERTY_HEADER_SIZE
        next_offset = value_offset + _aligned_size(length)
        if next_offset > end:
            raise DeviceTreeError(f"truncated property {name!r}")
        properties[name] = (cursor, value_offset, length)
        cursor = next_offset

    children = []
    for _ in range(child_count):
        child, cursor = _node_at(tree, cursor, end)
        children.append(child)

    return {"properties": properties, "children": children}, cursor


def parse(tree: bytearray):
    """Parse a complete flattened tree and return its root node."""
    root, consumed = _node_at(tree, 0, len(tree))
    if consumed > len(tree):
        raise DeviceTreeError("tree extends beyond its declared length")
    return root


def property_value(tree: bytearray, node, name: str) -> bytes:
    """Return one node property's unpadded value."""
    try:
        _, value_offset, length = node["properties"][name]
    except KeyError as error:
        raise DeviceTreeError(f"missing property {name!r}") from error
    return bytes(tree[value_offset : value_offset + length])


def child_named(tree: bytearray, node, name: str):
    """Find a direct child by its NUL-terminated ``name`` property."""
    expected = name.encode() + b"\0"
    for child in node["children"]:
        if "name" in child["properties"] and property_value(tree, child, "name") == expected:
            return child
    raise DeviceTreeError(f"missing child node {name!r}")


def replace_property(tree: bytearray, node, old_name: str, new_name: str, value: bytes):
    """Rename and replace an equal-sized property without moving the tree."""
    if len(new_name.encode()) >= PROPERTY_NAME_SIZE:
        raise DeviceTreeError("property name is too long")
    try:
        header_offset, value_offset, length = node["properties"][old_name]
    except KeyError as error:
        raise DeviceTreeError(f"missing property {old_name!r}") from error
    if len(value) != length:
        raise DeviceTreeError(
            f"property {old_name!r} is {length} bytes, replacement is {len(value)}"
        )

    encoded_name = new_name.encode() + b"\0"
    tree[header_offset : header_offset + PROPERTY_NAME_SIZE] = encoded_name.ljust(
        PROPERTY_NAME_SIZE, b"\0"
    )
    tree[value_offset : value_offset + length] = value
    node["properties"][new_name] = node["properties"].pop(old_name)

