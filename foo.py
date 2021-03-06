
from __future__ import print_function
import json
import os
import re
import subprocess
import sys
import time

def bash(command):
    proc = subprocess.Popen(command, 
                            shell=True, 
                            executable='/bin/bash', 
                            stderr=subprocess.PIPE, 
                            stdout=subprocess.PIPE)
    rc = proc.wait()
    (out, err) = proc.communicate() 
#     print ("Executed bash script: '{0}'".format(command))
#     print ("   Response code = {0}".format(rc))
#     print ("   Stdout = {0}".format(out))
#     print ("   Stderr = {0}".format(err))
    return {'rc' : rc,
            'stdout': out,
            'stderr': err
            }

def grp_info(group):
    cmd = "ice group inspect {group}".format(group=group)
    grp_info_s = re.sub("\s+", '', (bash(cmd)['stdout']))
    grp_info_json = json.loads(grp_info_s)
    return grp_info_json

def main():
    group_id = os.getenv('group_id')
    route = os.getenv('route')
#     print('X{}X'.format(group_id), file=sys.stderr)
    if group_id:
        grp = grp_info(group_id)
#         print(grp, file=sys.stderr)
        if grp and 'Routes' in grp and route in grp['Routes']:
            print(grp['Id'])
    
if __name__ == '__main__':
    main()
