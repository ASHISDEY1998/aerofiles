import os
import mimetypes
import shutil
import stat
from pathlib import Path
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Request, Response, UploadFile, File, Form, status
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="AeroFiles Home Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Root directory for browsing files
STORAGE_ROOT = Path(os.getenv("STORAGE_ROOT", "/storage")).resolve()
if not STORAGE_ROOT.exists():
    # Fallback to local 'storage' directory in current folder for local development
    STORAGE_ROOT = Path("./storage").resolve()
    STORAGE_ROOT.mkdir(parents=True, exist_ok=True)

STATIC_DIR = Path(__file__).parent / "static"

def resolve_safe_path(rel_path: str = "") -> Path:
    """Safely resolve user path against STORAGE_ROOT to prevent directory traversal."""
    cleaned = rel_path.strip().lstrip("/")
    target = (STORAGE_ROOT / cleaned).resolve()
    if not str(target).startswith(str(STORAGE_ROOT)):
        raise HTTPException(status_code=403, detail="Access denied: path outside storage root")
    return target

def get_file_category(name: str, is_dir: bool) -> str:
    if is_dir:
        return "folder"
    ext = Path(name).suffix.lower()
    if ext in [".mp4", ".mkv", ".mov", ".avi", ".webm", ".flv", ".wmv", ".m4v", ".ts", ".3gp"]:
        return "video"
    if ext in [".mp3", ".flac", ".wav", ".m4a", ".aac", ".ogg", ".opus", ".wma"]:
        return "audio"
    if ext in [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".heic", ".ico"]:
        return "image"
    if ext in [".pdf", ".doc", ".docx", ".txt", ".md", ".xls", ".xlsx", ".ppt", ".pptx", ".csv"]:
        return "document"
    if ext in [".zip", ".tar", ".gz", ".7z", ".rar", ".bz2", ".xz"]:
        return "archive"
    if ext in [".apk", ".aab"]:
        return "android"
    return "other"

def format_size(bytes_size: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB', 'TB', 'PB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.1f} {unit}" if unit != 'B' else f"{bytes_size} B"
        bytes_size /= 1024.0
    return f"{bytes_size:.1f} PB"

@app.get("/api/storage")
async def get_storage_stats():
    """Returns disk space usage for the storage root."""
    try:
        total, used, free = shutil.disk_usage(STORAGE_ROOT)
        percent = (used / total * 100) if total > 0 else 0
        return {
            "root": str(STORAGE_ROOT),
            "total_bytes": total,
            "used_bytes": used,
            "free_bytes": free,
            "total_formatted": format_size(total),
            "used_formatted": format_size(used),
            "free_formatted": format_size(free),
            "percent_used": round(percent, 1)
        }
    except Exception as e:
        return {
            "root": str(STORAGE_ROOT),
            "total_bytes": 0,
            "used_bytes": 0,
            "free_bytes": 0,
            "total_formatted": "Unknown",
            "used_formatted": "Unknown",
            "free_formatted": "Unknown",
            "percent_used": 0,
            "error": str(e)
        }

@app.get("/api/browse")
async def browse_directory(path: str = ""):
    """List directory contents with metadata."""
    target_dir = resolve_safe_path(path)
    if not target_dir.exists():
        raise HTTPException(status_code=404, detail="Directory not found")
    if not target_dir.is_dir():
        raise HTTPException(status_code=400, detail="Path is not a directory")

    rel_current = str(target_dir.relative_to(STORAGE_ROOT))
    if rel_current == ".":
        rel_current = ""

    parent_path = None
    if rel_current:
        parent_rel = str(target_dir.parent.relative_to(STORAGE_ROOT))
        parent_path = "" if parent_rel == "." else parent_rel

    items = []
    try:
        with os.scandir(target_dir) as entries:
            for entry in entries:
                # Ignore hidden files
                if entry.name.startswith("."):
                    continue
                try:
                    entry_stat = entry.stat()
                    is_dir = entry.is_dir(follow_symlinks=True)
                    size = entry_stat.st_size if not is_dir else 0
                    category = get_file_category(entry.name, is_dir)
                    mime, _ = mimetypes.guess_type(entry.name)

                    item_rel = str((target_dir / entry.name).relative_to(STORAGE_ROOT))

                    items.append({
                        "name": entry.name,
                        "path": item_rel,
                        "is_dir": is_dir,
                        "size": size,
                        "size_formatted": format_size(size) if not is_dir else "--",
                        "modified": int(entry_stat.st_mtime),
                        "category": category,
                        "mime": mime or ("directory" if is_dir else "application/octet-stream")
                    })
                except (OSError, PermissionError):
                    continue
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")

    # Sort: directories first, then alphabetical case-insensitive
    items.sort(key=lambda x: (not x["is_dir"], x["name"].lower()))

    # Build breadcrumb tokens
    breadcrumbs = []
    breadcrumbs.append({"name": "Storage Root", "path": ""})
    if rel_current:
        parts = rel_current.split("/")
        accum = ""
        for part in parts:
            accum = f"{accum}/{part}" if accum else part
            breadcrumbs.append({"name": part, "path": accum})

    return {
        "current_path": rel_current,
        "parent_path": parent_path,
        "breadcrumbs": breadcrumbs,
        "items": items,
        "total_count": len(items)
    }

@app.get("/api/stream")
async def stream_media(request: Request, path: str):
    """
    HTTP 206 Partial Content video and audio streaming server.
    Enables seeking on iOS Safari, Android, and desktop browsers.
    """
    target_file = resolve_safe_path(path)
    if not target_file.exists() or not target_file.is_file():
        raise HTTPException(status_code=404, detail="Media file not found")

    file_size = target_file.stat().st_size
    mime_type, _ = mimetypes.guess_type(target_file.name)
    if not mime_type:
        mime_type = "video/mp4"

    range_header = request.headers.get("range")

    if range_header:
        # Parse range header: e.g. "bytes=0-1048575"
        try:
            range_unit, range_spec = range_header.strip().split("=")
            if range_unit.lower() != "bytes":
                raise HTTPException(status_code=416, detail="Invalid range unit")

            start_str, end_str = range_spec.split("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
            if end >= file_size:
                end = file_size - 1

            if start > end or start >= file_size:
                raise HTTPException(
                    status_code=416,
                    headers={"Content-Range": f"bytes */{file_size}"},
                    detail="Requested Range Not Satisfiable"
                )

            chunk_size = (end - start) + 1

            def iter_chunk():
                with open(target_file, "rb") as f:
                    f.seek(start)
                    remaining = chunk_size
                    buffer_size = 1024 * 512 # 512KB
                    while remaining > 0:
                        read_bytes = min(remaining, buffer_size)
                        data = f.read(read_bytes)
                        if not data:
                            break
                        remaining -= len(data)
                        yield data

            headers = {
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(chunk_size),
                "Content-Type": mime_type,
            }
            return StreamingResponse(iter_chunk(), status_code=206, headers=headers)
        except (ValueError, IndexError):
            pass

    # Full file stream fallback
    def iter_full():
        with open(target_file, "rb") as f:
            while chunk := f.read(1024 * 512):
                yield chunk

    headers = {
        "Accept-Ranges": "bytes",
        "Content-Length": str(file_size),
        "Content-Type": mime_type,
    }
    return StreamingResponse(iter_full(), headers=headers)

@app.get("/api/download")
async def download_file(path: str):
    """Download single file as attachment."""
    target_file = resolve_safe_path(path)
    if not target_file.exists() or not target_file.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(
        path=target_file,
        filename=target_file.name,
        media_type="application/octet-stream"
    )

@app.post("/api/upload")
async def upload_files(
    target_path: str = Form(""),
    files: List[UploadFile] = File(...)
):
    """Upload one or more files into target directory."""
    dest_dir = resolve_safe_path(target_path)
    if not dest_dir.exists() or not dest_dir.is_dir():
        raise HTTPException(status_code=400, detail="Target directory does not exist")

    uploaded = []
    for upload in files:
        if not upload.filename:
            continue
        # Sanitize filename
        safe_filename = Path(upload.filename).name
        dest_file = dest_dir / safe_filename
        with open(dest_file, "wb") as f:
            while chunk := await upload.read(1024 * 1024):
                f.write(chunk)
        uploaded.append(safe_filename)

    return {"status": "success", "uploaded": uploaded, "count": len(uploaded)}

@app.post("/api/mkdir")
async def create_directory(path: str = Form(...), name: str = Form(...)):
    """Create a new directory."""
    parent_dir = resolve_safe_path(path)
    clean_name = name.strip().replace("/", "").replace("\\", "")
    if not clean_name:
        raise HTTPException(status_code=400, detail="Invalid folder name")
    new_dir = parent_dir / clean_name
    if new_dir.exists():
        raise HTTPException(status_code=400, detail="Folder already exists")
    new_dir.mkdir(parents=True, exist_ok=True)
    return {"status": "success", "name": clean_name}

@app.post("/api/rename")
async def rename_item(old_path: str = Form(...), new_name: str = Form(...)):
    """Rename file or folder."""
    target = resolve_safe_path(old_path)
    if not target.exists():
        raise HTTPException(status_code=404, detail="Item not found")
    clean_name = new_name.strip().replace("/", "").replace("\\", "")
    if not clean_name:
        raise HTTPException(status_code=400, detail="Invalid name")
    new_target = target.parent / clean_name
    if new_target.exists():
        raise HTTPException(status_code=400, detail="An item with that name already exists")
    target.rename(new_target)
    return {"status": "success", "new_name": clean_name}

@app.delete("/api/delete")
async def delete_item(path: str):
    """Delete a file or folder."""
    target = resolve_safe_path(path)
    if not target.exists():
        raise HTTPException(status_code=404, detail="Item not found")
    if target == STORAGE_ROOT:
        raise HTTPException(status_code=403, detail="Cannot delete storage root")

    if target.is_dir():
        shutil.rmtree(target)
    else:
        target.unlink()
    return {"status": "success"}

# Serve frontend static assets
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

@app.get("/")
async def serve_index():
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    return HTMLResponse("<h1>AeroFiles Home Server is running</h1>")

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8888"))
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=False)
