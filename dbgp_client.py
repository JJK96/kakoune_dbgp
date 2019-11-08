import socket
import sys
import threading
import _thread
import base64
from parsing import *
import kakoune as kak

i = 0
# Save unanswered requests, key=transaction_id, value=request
requests = {}

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
    tree = parse_response(response)
    pp1(tree)
    if 'command' in tree.attrib:
        command = tree.attrib['command']
        transaction_id = int(tree.attrib['transaction_id'])
        request = requests[transaction_id]
        del requests[transaction_id]
        print(request)
        if command == 'property_get':
            if len(tree) > 0:
                string = pp(tree[0])
                kak.info(string)
        elif command == 'context_get':
            for c in tree:
                kak.info(pp(c))
        elif command == 'breakpoint_set':
            active = True #TODO support inactive breakpoints
            line = request['-n']
            filename = request['-f']
            kak.handle_breakpoint_created(tree.attrib['id'], active, line, filename)
        elif command == 'breakpoint_remove':
            kak.handle_breakpoint_deleted(request['-d'])

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
    global i, requests
    requests[i] = parse_request(request)
    request += " -i " + str(i) + '\x00'
    request = bytes(request, 'utf-8')
    conn.send(request)
    i += 1

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
