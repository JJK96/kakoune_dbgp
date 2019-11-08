import os

session = None
client = None

def info(text):
    send_cmd("info %{{{}}}".format(text))

def debug(text):
    send_cmd("echo -debug %{{{}}}".format(text))

def handle_breakpoint_created(id_modified, active, line, filename):
    active = 1 if active else 0
    filename = filename[7:]
    send_cmd("dbgp-handle-breakpoint-created {} {} {} %{{{}}}".format(id_modified, active, line, filename))

def handle_breakpoint_deleted(id_modified):
    send_cmd("dbgp-handle-breakpoint-deleted {}".format(id_modified))

def send_cmd(cmd):
    cmd = cmd.replace('$', r'\$')
    cmd = "echo \"eval -client '{}' '{}'\" | kak -p {}".format(client, cmd, session)
    print(cmd)
    os.system(cmd)

