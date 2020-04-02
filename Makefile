install:
	mkdir -p /usr/local/share/lua/5.3/freechains/
	cp optparse.lua           /usr/local/share/lua/5.3/freechains/
	cp cfg.lua                /usr/local/share/lua/5.3/freechains/
	cp ui.lua                 /usr/local/share/lua/5.3/freechains/
	cp freechains-liferea.lua /usr/local/bin/freechains-liferea
	cp freechains-dot.lua     /usr/local/bin/freechains-dot
