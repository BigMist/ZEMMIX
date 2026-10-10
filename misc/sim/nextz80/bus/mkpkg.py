import sys
prog=open(sys.argv[1],'rb').read()
mem={}
boot={0:b'\xc3\x10\x00',5:b'\x7b\xd3\x01\xc9',0x10:b'\x31\x00\xf0\x21\x40\x00\xe5\xc3\x00\x01',0x40:b'\x76',0x100:prog}
for a,bs in boot.items():
    for i,v in enumerate(bs): mem[a+i]=v
lines=",\n".join(f'    16#{a:04X}# => x"{v:02X}"' for a,v in sorted(mem.items()))
open(sys.argv[2],'w').write(f'''library ieee;
use ieee.std_logic_1164.all;
package prog_pkg is
  type mem_t is array(0 to 65535) of std_logic_vector(7 downto 0);
  constant PROG : mem_t := (
{lines},
    others => x"00");
end package;
''')
