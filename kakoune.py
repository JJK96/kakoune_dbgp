import os
from parsing import convert_filename
from dbgp_client import DEBUG

session = None
client = None

def info(text):
    send_cmd("info %{{{}}}".format(text))

def debug(text):
    if DEBUG:
        send_cmd("echo -debug %{{{}}}".format(text))

def handle_breakpoint_created(id_modified, active, line, filename):
    active = 1 if active else 0
    filename = convert_filename(filename)
    send_cmd("dbgp-handle-breakpoint-created {} {} {} %{{{}}}".format(id_modified, active, line, filename))

def handle_breakpoint_deleted(id_modified):
    send_cmd("dbgp-handle-breakpoint-deleted {}".format(id_modified))

def handle_running():
    send_cmd("dbgp-handle-running")

def handle_eval(result):
    send_cmd("dbgp-handle-eval %{{{}}}".format(result))

def handle_stacktrace(result):
    send_cmd("dbgp-handle-stacktrace %{{{}}}".format(result))

def handle_break(line, filename):
    filename = convert_filename(filename)
    send_cmd("dbgp-handle-break {} %{{{}}}".format(line, filename))

def handle_stopped():
    send_cmd("dbgp-handle-stopped")

def handle_context(variable):
    # Show the current context (variables) in the context buffer
    send_cmd("dbgp-handle-context %{{{}}}".format(variable))

def send_cmd(cmd):
    cmd = cmd.replace("'", r"'\''")
    cmd = "echo 'eval -client %{{{}}} %{{{}}}' | kak -p {}".format(client, cmd, session)
    print(cmd)
    os.system(cmd)

