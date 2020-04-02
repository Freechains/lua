install:
	mkdir -p /usr/local/share/lua/5.3/freechains/
	cp optparse.lua /usr/local/share/lua/5.3/
	cp cfg.lua	    /usr/local/share/lua/5.3/freechains/
	cp ui.lua	    /usr/local/share/lua/5.3/freechains/
	cp liferea.lua  /usr/local/bin/freechains-liferea
	cp dot.lua	    /usr/local/bin/freechains-dot
