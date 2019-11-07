import base64
import xml.etree.ElementTree as ET
from xml.dom.minidom import parseString
from html import unescape

def pp(tree, indent=0):
    pp1(tree)
    children = 'children' in tree.attrib and tree.attrib['children']
    text = None
    if tree.text:
        text = tree.text
        if 'encoding' in tree.attrib and tree.attrib['encoding'] == 'base64':
            text = base64.b64decode(bytes(tree.text, 'utf-8')).decode()

    string = "  "*indent + tree.attrib['fullname'] + \
        (': ' + text if tree.text else '') + \
        (' > ' +tree.attrib['numchildren'] if children else '') + "\n"

    for child in tree:
        string += pp(child, indent + 1)
    return string

def pp1(tree):
    parsed = parseString(ET.tostring(tree))
    print(unescape(parsed.toprettyxml(indent="\t")))
