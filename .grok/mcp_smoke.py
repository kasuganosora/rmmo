import json, socket, sys, os

HOST, PORT = "127.0.0.1", 18765

class Mcp:
    def __init__(self):
        self.s = socket.create_connection((HOST, PORT), timeout=60)
        self.s.settimeout(60)
        self.buf = b""
        self.rid = 0

    def _read_http(self):
        while b"\r\n\r\n" not in self.buf:
            chunk = self.s.recv(65536)
            if not chunk:
                raise RuntimeError("eof headers")
            self.buf += chunk
        head, rest = self.buf.split(b"\r\n\r\n", 1)
        headers = head.decode("latin1", "replace")
        clen = 0
        for line in headers.split("\r\n"):
            if line.lower().startswith("content-length:"):
                clen = int(line.split(":",1)[1].strip())
        while len(rest) < clen:
            chunk = self.s.recv(65536)
            if not chunk:
                break
            rest += chunk
        body, self.buf = rest[:clen], rest[clen:]
        return json.loads(body.decode("utf-8"))

    def rpc(self, method, params=None):
        self.rid += 1
        msg = {"jsonrpc":"2.0","id":self.rid,"method":method,"params":params or {}}
        body = json.dumps(msg, separators=(",",":")).encode()
        req = b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"%len(body) + body
        self.s.sendall(req)
        return self._read_http()

    def call(self, name, args=None):
        r = self.rpc("tools/call", {"name": name, "arguments": args or {}})
        if "error" in r:
            return {"ok": False, "rpc_error": r["error"]}
        content = r.get("result", {}).get("content", [])
        text = None
        has_img = False
        for c in content:
            if c.get("type") == "image":
                has_img = True
            if c.get("type") == "text":
                text = c.get("text")
        data = json.loads(text) if text else {}
        data["_has_image"] = has_img
        return data

m = Mcp()
info = m.rpc("initialize", {"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}})
print("SERVER", info.get("result",{}).get("serverInfo"))
listed = m.rpc("tools/list", {})
tools = [t["name"] for t in listed.get("result",{}).get("tools",[])]
print("TOOL_COUNT", len(tools))
need = ["preview_tileset","paint_rect","paint_polyline","paint_ring","preview_map","get_tile","create_map","delete_map","get_map_settings","paint_fill","undo"]
for n in need:
    print(("HAVE" if n in tools else "MISS"), n)
st = m.call("editor_state")
print("STATE", {k: st.get(k) for k in ["ok","pack_id","map_id","width","height","tileset_id","layer_z","error"]})
maps = m.call("list_maps")
print("MAPS", maps.get("maps"))
ts = m.call("list_tilesets")
print("TILESETS", [{k:x.get(k) for k in ["id","name","current"]} for x in ts.get("tilesets",[])])
prev = m.call("preview_tileset", {"tab":"A","max_px":640})
print("TILESET_PREV", {k: prev.get(k) for k in ["ok","tab","tileset_id","count","px_w","px_h","path","saved","_has_image","error"]})
if prev.get("catalog"):
    # print a few interesting ids
    cat = prev["catalog"]
    print("CAT0", cat[0], "CAT16", cat[16] if len(cat)>16 else None, "CAT48", cat[48] if len(cat)>48 else None)
created = m.call("create_map", {"map_id":"MCPSmoke","name":"MCP冒烟","w":48,"h":48,"tileset":"outside"})
print("CREATE", {k: created.get(k) for k in ["ok","map_id","width","height","error"]})
# water A1 kind 0 = 2048, grass A2 kind 16 = 2816, dirt kind 24 = 2048+24*48=3200
grass=2816
dirt=2048+24*48
water=2048
r1 = m.call("paint_rect", {"x":0,"y":0,"w":48,"h":48,"tile_id":grass,"z":0})
print("GRASS", {k:r1.get(k) for k in ["ok","painted","error"]})
r2 = m.call("paint_polyline", {"points":[{"x":8,"y":4},{"x":12,"y":20},{"x":24,"y":28},{"x":36,"y":40}],"tile_id":water,"width":3,"z":0})
print("RIVER", {k:r2.get(k) for k in ["ok","painted","error"]})
r3 = m.call("paint_ring", {"x":24,"y":24,"r":16,"thickness":2,"tile_id":dirt,"z":0})
print("WALL", {k:r3.get(k) for k in ["ok","painted","error"]})
gt = m.call("get_tile", {"x":24,"y":24})
print("GET_CENTER", {k:gt.get(k) for k in ["ok","z","meta","error"]})
pm = m.call("preview_map", {"x":0,"y":0,"w":48,"h":48,"grid":True,"entities":True,"max_px":768})
print("PREVIEW", {k:pm.get(k) for k in ["ok","w","h","px_w","px_h","path","saved","_has_image","error"]})
# cleanup
dlt = m.call("delete_map", {"map_id":"MCPSmoke"})
print("DELETE", {k:dlt.get(k) for k in ["ok","deleted","map_id","error"]})
st2 = m.call("editor_state")
print("AFTER", st2.get("map_id"), st2.get("width"))
