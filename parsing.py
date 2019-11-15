import base64
import xml.etree.ElementTree as ET
from xml.dom.minidom import parseString
from html import unescape

INDENT_SIZE = 2

def format_variables(tree, indent=0):
    print_response(tree)
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
        string += format_variables(child, indent + INDENT_SIZE)
    return string

def format_stacktrace(stacktrace):
    string = ""
    for function in stacktrace:
        if function.attrib['type'] == 'file':
            level = function.attrib['level']
            where = function.attrib['where']
            lineno = function.attrib['lineno']
            filename = convert_filename(function.attrib['filename'])
            string += "{}: at {} ({}:{})\n".format(level, where, filename, lineno)
        else:
            string += ET.tostring(function) + "\n"
    return string

def print_response(tree):
    parsed = parseString(ET.tostring(tree))
    print(unescape(parsed.toprettyxml(indent="\t")))

def parse_response(response):
    return ET.fromstring(response)

def convert_filename(filename):
    """ remove file:// """
    return filename[7:]

class Request:
    def __init__(self, request_string):
        self.parse(request_string)

    def parse(self, request):
        """ from string to class properties """
        request_data = request.split(' -- ')
        if len(request_data) == 2:
            request, data = request_data
            data = data.lstrip()
        else:
            request = request_data[0]
            data = None
        request = request.split(' ')
        self.client = request.pop(0)
        self.extra = request.pop(0)
        self.command = request.pop(0)
        self.data = data
        self.args = {}
        for i in range(0, len(request)-1, 2):
            self.args[request[i]] = request[i+1]

    def compose(self, transaction_id):
        """ from dict to string """
        cmd_string = self.command + " -i " + str(transaction_id)
        for arg, val in self.args.items():
            cmd_string += ' ' + arg + ' ' + val
        if self.data:
            cmd_string += ' -- ' + base64.b64encode(self.data.encode()).decode()
        cmd_string += '\x00'
        return cmd_string

    def __str__(self):
        return str(self.__dict__)
