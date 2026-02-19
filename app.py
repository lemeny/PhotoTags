import argparse
import hashlib
import json
import math
import sqlite3
from pathlib import Path
from uuid import uuid4

from flask import Flask, flash, redirect, render_template, request, send_from_directory, url_for
from PIL import Image
from pillow_heif import register_heif_opener
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "uploads"
DB_PATH = BASE_DIR / "phototags.db"
ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"}
PAGE_SIZE = 120

app = Flask(__name__)
app.secret_key = "phototags-dev-key"
UPLOAD_DIR.mkdir(exist_ok=True)
register_heif_opener()


def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    return conn


def init_db():
    with get_db_connection() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS photos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL,
                original_name TEXT NOT NULL,
                file_sha256 TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL
            );

            CREATE TABLE IF NOT EXISTS photo_tags (
                photo_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY (photo_id, tag_id),
                FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE,
                FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_photos_created_at ON photos(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_photos_sha256 ON photos(file_sha256);
            CREATE INDEX IF NOT EXISTS idx_photo_tags_tag_photo ON photo_tags(tag_id, photo_id);
            CREATE INDEX IF NOT EXISTS idx_photo_tags_photo_tag ON photo_tags(photo_id, tag_id);
            """
        )

        columns = {row["name"] for row in conn.execute("PRAGMA table_info(photos)")}
        if "file_sha256" not in columns:
            conn.execute("ALTER TABLE photos ADD COLUMN file_sha256 TEXT")
            conn.commit()


def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def get_file_extension(filename: str) -> str | None:
    if "." not in filename:
        return None
    extension = filename.rsplit(".", 1)[1].lower()
    return extension or None


def parse_tags(raw: str) -> list[str]:
    cleaned = [tag.strip() for tag in raw.replace("，", ",").split(",")]
    return sorted({tag for tag in cleaned if tag})


def sha256_of_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def attach_tags(conn: sqlite3.Connection, photo_id: int, tags: list[str]):
    for tag_name in tags:
        conn.execute("INSERT OR IGNORE INTO tags(name) VALUES (?)", (tag_name,))
        tag_row = conn.execute("SELECT id FROM tags WHERE name = ?", (tag_name,)).fetchone()
        conn.execute(
            "INSERT OR IGNORE INTO photo_tags(photo_id, tag_id) VALUES (?, ?)",
            (photo_id, tag_row["id"]),
        )


def save_uploaded_image(file_storage, extension: str) -> tuple[str, str]:

    if extension in {"heic", "heif"}:
        unique_name = f"{uuid4().hex}.jpg"
        image = Image.open(file_storage.stream)
        rgb_image = image.convert("RGB")
        target_path = UPLOAD_DIR / unique_name
        rgb_image.save(target_path, format="JPEG", quality=92)
        return unique_name, sha256_of_file(target_path)

    unique_name = f"{uuid4().hex}.{extension}"
    target_path = UPLOAD_DIR / unique_name
    file_storage.save(target_path)
    return unique_name, sha256_of_file(target_path)


def get_tags_by_photo_ids(conn: sqlite3.Connection, photo_ids: list[int]) -> dict[int, list[str]]:
    if not photo_ids:
        return {}

    placeholders = ",".join("?" for _ in photo_ids)
    rows = conn.execute(
        f"""
        SELECT pt.photo_id, t.name
        FROM photo_tags pt
        JOIN tags t ON t.id = pt.tag_id
        WHERE pt.photo_id IN ({placeholders})
        ORDER BY t.name COLLATE NOCASE
        """,
        photo_ids,
    ).fetchall()

    tags_by_photo: dict[int, list[str]] = {}
    for row in rows:
        tags_by_photo.setdefault(row["photo_id"], []).append(row["name"])
    return tags_by_photo


def build_sync_payload(conn: sqlite3.Connection) -> dict:
    photos = conn.execute("SELECT id, original_name, file_sha256 FROM photos").fetchall()
    photo_ids = [photo["id"] for photo in photos]
    tags_by_photo = get_tags_by_photo_ids(conn, photo_ids)
    payload_photos = []

    for photo in photos:
        payload_photos.append(
            {
                "original_name": photo["original_name"],
                "file_sha256": photo["file_sha256"],
                "tags": tags_by_photo.get(photo["id"], []),
            }
        )

    return {"version": 1, "photos": payload_photos}


def export_sync_file(output_path: Path):
    init_db()
    with get_db_connection() as conn:
        payload = build_sync_payload(conn)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def import_sync_file(input_path: Path):
    init_db()
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    photos = payload.get("photos", [])

    with get_db_connection() as conn:
        for item in photos:
            tags = parse_tags(",".join(item.get("tags", [])))
            sha256 = item.get("file_sha256")
            original_name = item.get("original_name", "")
            existing = None

            if sha256:
                existing = conn.execute(
                    "SELECT id FROM photos WHERE file_sha256 = ? LIMIT 1", (sha256,)
                ).fetchone()

            if not existing and original_name:
                existing = conn.execute(
                    "SELECT id FROM photos WHERE original_name = ? ORDER BY id DESC LIMIT 1",
                    (original_name,),
                ).fetchone()

            if existing:
                attach_tags(conn, existing["id"], tags)

        conn.commit()


def parse_page(value: str | None) -> int:
    try:
        page = int(value or "1")
    except ValueError:
        return 1
    return page if page > 0 else 1


@app.route("/")
def index():
    selected_tags = [tag for tag in request.args.getlist("tag") if tag]
    page = parse_page(request.args.get("page"))
    offset = (page - 1) * PAGE_SIZE

    with get_db_connection() as conn:
        all_tags = conn.execute("SELECT id, name FROM tags ORDER BY name COLLATE NOCASE").fetchall()

        if selected_tags:
            placeholders = ",".join("?" for _ in selected_tags)
            total_count = conn.execute(
                f"""
                SELECT COUNT(*) AS total_count
                FROM (
                    SELECT p.id
                    FROM photos p
                    JOIN photo_tags pt ON pt.photo_id = p.id
                    JOIN tags t ON t.id = pt.tag_id
                    WHERE t.name IN ({placeholders})
                    GROUP BY p.id
                    HAVING COUNT(DISTINCT t.name) = ?
                ) filtered
                """,
                (*selected_tags, len(selected_tags)),
            ).fetchone()["total_count"]

            photos = conn.execute(
                f"""
                SELECT p.id, p.filename, p.original_name
                FROM photos p
                JOIN photo_tags pt ON pt.photo_id = p.id
                JOIN tags t ON t.id = pt.tag_id
                WHERE t.name IN ({placeholders})
                GROUP BY p.id
                HAVING COUNT(DISTINCT t.name) = ?
                ORDER BY p.created_at DESC
                LIMIT ? OFFSET ?
                """,
                (*selected_tags, len(selected_tags), PAGE_SIZE, offset),
            ).fetchall()
        else:
            total_count = conn.execute("SELECT COUNT(*) AS total_count FROM photos").fetchone()[
                "total_count"
            ]
            photos = conn.execute(
                """
                SELECT id, filename, original_name
                FROM photos
                ORDER BY created_at DESC
                LIMIT ? OFFSET ?
                """,
                (PAGE_SIZE, offset),
            ).fetchall()

        photo_ids = [photo["id"] for photo in photos]
        tags_by_photo = get_tags_by_photo_ids(conn, photo_ids)

    total_pages = max(1, math.ceil(total_count / PAGE_SIZE))
    if page > total_pages:
        return redirect(url_for("index", tag=selected_tags, page=total_pages))

    return render_template(
        "index.html",
        photos=photos,
        all_tags=all_tags,
        tags_by_photo=tags_by_photo,
        selected_tags=selected_tags,
        page=page,
        total_pages=total_pages,
        total_count=total_count,
        page_size=PAGE_SIZE,
    )


@app.route("/upload", methods=["POST"])
def upload_photo():
    file = request.files.get("photo")
    tags = parse_tags(request.form.get("tags", ""))

    if not file or not file.filename:
        flash("请先选择图片。", "error")
        return redirect(url_for("index"))

    if not allowed_file(file.filename):
        flash("仅支持常见图片格式（jpg/png/gif/webp/bmp/heic/heif）。", "error")
        return redirect(url_for("index"))

    extension = get_file_extension(file.filename)
    if not extension:
        flash("无法解析文件扩展名，请重命名后重试。", "error")
        return redirect(url_for("index"))

    original_name = secure_filename(file.filename) or f"upload.{extension}"
    unique_name, file_sha256 = save_uploaded_image(file, extension)

    with get_db_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO photos(filename, original_name, file_sha256) VALUES (?, ?, ?)",
            (unique_name, original_name, file_sha256),
        )
        attach_tags(conn, cursor.lastrowid, tags)
        conn.commit()

    flash("图片已上传并保存标签。", "success")
    return redirect(url_for("index"))


@app.route("/photos/<path:filename>")
def serve_photo(filename: str):
    return send_from_directory(UPLOAD_DIR, filename)


@app.route("/photos/<int:photo_id>/tags", methods=["POST"])
def add_tags(photo_id: int):
    tags = parse_tags(request.form.get("tags", ""))
    if not tags:
        flash("请输入至少一个标签。", "error")
        return redirect(url_for("index"))

    with get_db_connection() as conn:
        photo = conn.execute("SELECT id FROM photos WHERE id = ?", (photo_id,)).fetchone()
        if not photo:
            flash("图片不存在。", "error")
            return redirect(url_for("index"))

        attach_tags(conn, photo_id, tags)
        conn.commit()

    flash("标签添加成功。", "success")
    return redirect(url_for("index"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PhotoTags local app")
    parser.add_argument("--export-sync", help="导出标签同步文件，例如 sync/phototags_sync.json")
    parser.add_argument("--import-sync", help="导入标签同步文件并合并到当前数据库")
    args = parser.parse_args()

    if args.export_sync:
        export_path = Path(args.export_sync)
        export_path.parent.mkdir(parents=True, exist_ok=True)
        export_sync_file(export_path)
        print(f"已导出标签同步文件：{export_path}")
    elif args.import_sync:
        import_sync_file(Path(args.import_sync))
        print("已导入标签同步文件。")
    else:
        init_db()
        app.run(host="127.0.0.1", port=5000, debug=True)
