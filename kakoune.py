import os

session = None
client = None

def info(text):
    send_cmd("info %{{{}}}".format(text))

def debug(text):
    send_cmd("echo -debug %{{{}}}".format(text))

def send_cmd(cmd):
    cmd = cmd.replace('$', r'\$')
    cmd = "echo \"eval -client '{}' '{}'\" | kak -p {}".format(client, cmd, session)
    print(cmd)
    os.system(cmd)

