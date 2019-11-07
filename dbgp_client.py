import socket
import sys
import threading
import _thread
import xml.etree.ElementTree as ET
import base64
from xml_format import *
import kakoune as kak

i = 0

def usage():
    print("usage: {} <port> <kakoune_session> <kakoune_client>".format(sys.argv[0]))
    exit()

if len(sys.argv) < 4:
    usage()

try:
    port = int(sys.argv[1])
    kak.session = sys.argv[2]
    kak.client = sys.argv[3]
except:
    usage()

def handle_response(response):
    kak.info(response)
    tree = ET.fromstring(response)
    pp1(tree)
    if 'command' in tree.attrib:
        if tree.attrib['command'] == 'property_get':
            if len(tree) > 0:
                string = pp(tree[0])
                kak.info(string)
        elif tree.attrib['command'] == 'context_get':
            for c in tree:
                kak.info(pp(c))

def receive(conn):
    response = bytes()
    while True:
        data = conn.recv(1024)
        if not data:
            break
        response += data
        if data[-1] == 0:
            r = response.split(b'\x00')[1].decode()
            r = r.split('\n')
            handle_response(r[1])
            response = bytes()

def send(conn, request):
    global i
    request += " -i " + str(i) + '\x00'
    i += 1
    request = bytes(request, 'utf-8')
    conn.send(request)

def handle_stdin(conn):
    for line in sys.stdin:
        if line[:-1] == "exit()":
            sys.exit()
        kak.debug(line)
        space = line.index(' ')
        kak.client = line[:space]
        send(conn, line[space+1:-1]) #remove newline

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(('0.0.0.0', port))
    s.listen()
    conn, addr = s.accept()
    try:
        print("connected")
        t = threading.Thread(target=receive, args=(conn,))
        t.daemon = True
        t.start()
        handle_stdin(conn)
    finally:
        conn.close()
