import sys
S=sys.argv[1]; prog=sys.argv[2]
src=open(S+'/mkd.py').read().replace("sys.argv[1]","S").replace("sys.argv[2]","'prog_pkg.vhd'")
head=src[:src.index("# ---- main at 0100")].replace("a.b(0x31, 0x00, 0xF0); a.jp('main')","a.b(0x31, 0x00, 0xF0); a.jp('main2')")
exec(head)
a.lab('main2'); a.b(0x3E,0x02); a.call('chgcpu'); a.b(0xCD,0x00,0x01); a.b(0x3E,0x00); a.call('chgcpu'); a.b(0x76)
code=bytearray(a.resolve()); code += bytes(0x100-len(code)) + open(S+'/'+prog,'rb').read()
lines=",\n".join(f'    16#{i:04X}# => x"{v:02X}"' for i,v in enumerate(code) if v)
open('prog_pkg.vhd','w').write("library ieee;\nuse ieee.std_logic_1164.all;\npackage prog_pkg is\n  type mem_t is array(0 to 65535) of std_logic_vector(7 downto 0);\n  constant PROG : mem_t := (\n"+lines+",\n    others => x\"00\");\nend package;\n")
