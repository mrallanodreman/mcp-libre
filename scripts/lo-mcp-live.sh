#!/bin/bash
#
# lo-mcp-live.sh — arranca el servidor HTTP en vivo (:8765) de la extensión
# mcp-libre dentro de LibreOffice.
#
# Requiere: la extensión org.mcp.libreoffice.extension instalada (unopkg list).
# Uso:      scripts/lo-mcp-live.sh [/ruta/al/documento.odt]
#
# El documento dado se abre en el LibreOffice GUI. El servidor HTTP :8765
# edita ESE documento abierto en vivo (edición in-place, feedback visual).

set -e

DOC="${1:-}"
LO_SOCKET="socket,host=127.0.0.1,port=2002;urp;"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$HERE/scripts/_dispatch_start_mcp.py"

# 1) Asegurar que LibreOffice esté corriendo (con socket UNO en :2002)
if ! pgrep -x soffice.bin >/dev/null 2>&1 && ! pgrep -f "soffice.*2002" >/dev/null 2>&1; then
    echo "🟢 Lanzando LibreOffice..."
    if [ -n "$DOC" ]; then
        setsid nohup soffice --accept="$LO_SOCKET" "$DOC" >/tmp/lo-mcp-live.log 2>&1 </dev/null &
    else
        setsid nohup soffice --accept="$LO_SOCKET" >/tmp/lo-mcp-live.log 2>&1 </dev/null &
    fi
    for i in $(seq 1 30); do
        sleep 1
        ss -tln 2>/dev/null | grep -q 2002 && break
    done
    ss -tln 2>/dev/null | grep -q 2002 || { echo "❌ LibreOffice no abrió el socket UNO :2002"; exit 1; }
    echo "✅ LibreOffice arriba (UNO :2002)"
else
    echo "✅ LibreOffice ya estaba corriendo"
fi

# 2) Disparar Start MCP Server de la extensión vía UNO dispatch
cat > "$DISPATCH" <<'PYEOF'
import uno
import sys

localContext = uno.getComponentContext()
resolver = localContext.ServiceManager.createInstanceWithContext(
    "com.sun.star.bridge.UnoUrlResolver", localContext)
ctx = resolver.resolve("uno:socket,host=127.0.0.1,port=2002;urp;StarOffice.ComponentContext")
smgr = ctx.ServiceManager
desktop = smgr.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
frame = desktop.getCurrentFrame()
if not frame:
    frame = desktop.getFrames().getByIndex(0)
dh = smgr.createInstanceWithContext("com.sun.star.frame.DispatchHelper", ctx)
url = "service:org.mcp.libreoffice.MCPExtension?start_mcp_server"
dh.executeDispatch(frame, url, "", 0, ())
print("dispatch start_mcp_server OK")
PYEOF
python3 "$DISPATCH" 2>/dev/null | tail -1 || { echo "⚠️  No se pudo hacer dispatch (¿extensión instalada?)"; }

# 3) Esperar a que el HTTP :8765 esté arriba
for i in $(seq 1 15); do
    sleep 1
    if curl -s -o /dev/null http://localhost:8765/health; then
        echo "✅ MCP live arriba: http://localhost:8765 (salud: $(curl -s http://localhost:8765/health | tr -d '\n'))"
        exit 0
    fi
done
echo "❌ El HTTP :8765 no respondió a tiempo. ¿Está instalada la extensión? (unopkg list | grep org.mcp)"
exit 1
