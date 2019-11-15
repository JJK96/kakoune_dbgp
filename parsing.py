import base64
import xml.etree.ElementTree as ET
from xml.dom.minidom import parseString
from html import unescape

INDENT_SIZE = 2

def pp(tree, indent=0):
    pp1(tree)
    children = 'children' in tree.attrib and tree.attrib['children']
    text = None
    if tree.text:
        text = tree.text
        if 'encoding' in tree.attrib and tree.attrib['encoding'] == 'base64':
            text = base64.b64decode(bytes(tree.text, 'utf-8')).decode()

    if 'fullname' in tree.attrib:
        name = tree.attrib['fullname']
    elif 'classname' in tree.attrib:
        name = tree.attrib['classname']
    elif 'name' in tree.attrib:
        name = tree.attrib['name']
    else:
        name = ''
    string = " "*indent + name + \
        (': ' if name and text else '') + \
        (text if text else '') + \
        (' > ' +tree.attrib['numchildren'] if children else '') + "\n"

    for child in tree:
        string += pp(child, indent + INDENT_SIZE)
    return string

def pp1(tree):
    parsed = parseString(ET.tostring(tree))
    print(unescape(parsed.toprettyxml(indent="\t")))

def parse_response(response):
    return ET.fromstring(response)

def parse_request(request):
    request_data = request.split(' -- ')
    if len(request_data) == 2:
        request, data = request_data
        data = data.lstrip()
    else:
        request = request_data[0]
        data = None
    request = request.split(' ')
    parsed = {}
    parsed['client'] = request.pop(0)
    parsed['extra'] = request.pop(0)
    parsed['cmd_string'] = ' '.join(request)
    parsed['command'] = request.pop(0)
    parsed['data'] = data
    for i in range(0, len(request)-1, 2):
        parsed[request[i]] = request[i+1]
    return parsed
