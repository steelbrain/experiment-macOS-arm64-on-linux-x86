import importlib.util
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts/27on86/apple_device_tree.py"
SPEC = importlib.util.spec_from_file_location("apple_device_tree", HELPER)
apple_device_tree = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(apple_device_tree)


def prop(name, value):
    header = name.encode().ljust(32, b"\0") + struct.pack("<I", len(value))
    return header + value.ljust((len(value) + 3) & ~3, b"\0")


def node(properties, children=()):
    return bytearray(
        struct.pack("<II", len(properties), len(children))
        + b"".join(prop(name, value) for name, value in properties)
        + b"".join(children)
    )


class AppleDeviceTreeTests(unittest.TestCase):
    def test_replaces_equal_sized_property_in_named_child(self):
        asmb = node((("name", b"asmb\0"), ("lp-stng", struct.pack("<Q", 1))))
        chosen = node((("name", b"chosen\0"),), (asmb,))
        tree = node((("name", b"device-tree\0"),), (chosen,))

        root = apple_device_tree.parse(tree)
        chosen_node = apple_device_tree.child_named(tree, root, "chosen")
        asmb_node = apple_device_tree.child_named(tree, chosen_node, "asmb")
        apple_device_tree.replace_property(
            tree, asmb_node, "lp-stng", "lp-sip0", struct.pack("<Q", 2)
        )

        reparsed = apple_device_tree.parse(tree)
        chosen_node = apple_device_tree.child_named(tree, reparsed, "chosen")
        asmb_node = apple_device_tree.child_named(tree, chosen_node, "asmb")
        self.assertEqual(
            apple_device_tree.property_value(tree, asmb_node, "lp-sip0"),
            struct.pack("<Q", 2),
        )
        self.assertNotIn("lp-stng", asmb_node["properties"])

    def test_rejects_a_different_sized_replacement(self):
        tree = node((("name", b"root\0"), ("old", b"1234")))
        root = apple_device_tree.parse(tree)
        with self.assertRaisesRegex(apple_device_tree.DeviceTreeError, "4 bytes"):
            apple_device_tree.replace_property(tree, root, "old", "new", b"12345678")

    def test_rejects_truncated_property(self):
        tree = bytearray(struct.pack("<II", 1, 0) + b"short")
        with self.assertRaisesRegex(apple_device_tree.DeviceTreeError, "truncated"):
            apple_device_tree.parse(tree)


if __name__ == "__main__":
    unittest.main()
