import socket
import sys
import threading
import base64
from parsing import *
import kakoune as kak

# DEBUG
DEBUG = False
DEBUG_OUTPUT = "/tmp/kakoune_dbgp_client"

# Transaction ID
i = 0
# Save unanswered requests, key=transaction_id, value=request
requests = {}

def usage():
    debug("usage: {} <port> <kakoune_session> <kakoune_client>".format(sys.argv[0]))
    exit()

if len(sys.argv) < 4:
    usage()

if DEBUG and DEBUG_OUTPUT:
    f = open(DEBUG_OUTPUT, 'w')
    sys.stdout = f
    sys.stderr = f

try:
    port = int(sys.argv[1])
    kak.session = sys.argv[2]
    kak.client = sys.argv[3]
except:
    usage()

def handle_response(response):
    kak.debug(response)
    tree = parse_response(response)
    print_response(tree)
    if 'command' in tree.attrib:
        command = tree.attrib['command']
        if not 'transaction_id' in tree.attrib:
            kak.info(response)
            return
        transaction_id = int(tree.attrib['transaction_id'])
        request = requests[transaction_id]
        del requests[transaction_id]
        debug(request)
        if command == 'status':
            kak.info(response)
            return
        elif command == 'property_get':
            if len(tree) > 0:
                if request.extra:
                    indent = int(request.extra)
                else:
                    indent = 0
                string = format_variables(tree[0], indent)
                kak.handle_property(string)
            return
        elif command == 'context_get':
            string = ""
            for c in tree:
                string += format_variables(c)
            kak.handle_context(string)
            return
        elif command == 'eval':
            if len(tree) > 0:
                string = format_variables(tree[0])
                kak.handle_eval(string)
                return
        elif command == 'breakpoint_set':
            active = True #TODO support inactive breakpoints
            line = request.args['-n']
            filename = request.args['-f']
            kak.handle_breakpoint_created(tree.attrib['id'], active, line, filename)
            return
        elif command == 'breakpoint_remove':
            kak.handle_breakpoint_deleted(request.args['-d'])
            return
        elif command == 'stack_get':
            kak.handle_stacktrace(format_stacktrace(tree))
            return
    if 'status' in tree.attrib:
        status = tree.attrib['status']
        if status == 'break':
            line = tree[0].attrib['lineno']
            filename = tree[0].attrib['filename']
            kak.handle_break(line, filename)
            return
        if status == 'stopping':
            kak.handle_stopped()
            return
    kak.info(response)

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
    cmd_string = request.compose(i)
    cmd = cmd_string.encode()
    conn.send(cmd)
    debug(cmd)
    i += 1

def handle_stdin(conn):
    global requests
    for line in sys.stdin:
        line = line[:-1] # remove newline
        if line == "exit()":
            sys.exit()
        kak.debug(line)
        request = Request(line)
        handle_request(conn, request)

def handle_request(conn, request):
    requests[i] = request
    kak.client = request.client
    command = request.command
    if command == 'run' or command.startswith('step'):
        kak.handle_running()
    send(conn, request) 

def debug(message):
    if DEBUG:
        print(message)

if __name__ == '__main__':
    debug("started")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(('0.0.0.0', port))
        s.listen()
        conn, addr = s.accept()
        try:
            debug("connected")
            t = threading.Thread(target=receive, args=(conn,))
            t.daemon = True
            t.start()
            handle_stdin(conn)
        finally:
            conn.close()
