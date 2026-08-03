I wanna create a tool that

when run,

$ cubrid-ini-fzf

it loads all possible changes in cubrid conf

(which might be available with cubrid paramdump. This might be SA mode or CS mode)
If the server is up (checked with cubrid server status), you should use cubrid paramdump
if the server is down, you can use cubrid paramdump -S (standalone mode)
Check the outputs and create the script.

and when I type something, it must match the corresponding entry

if I press ctrl c it quits

if I press enter, it goes to the next step where I update the value.

If I type something, it must use ini.sh tool (which must be available in the path, otherwise error in the first place)

and update the cubrid.conf file with the corresponding value.

It must ask you to stop the server since the setting must be applied.


