import sys
import json
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from converters.pdf_converter import PDFConverter


class ConversionHandler(BaseHTTPRequestHandler):
    _converters = None
    _reverse_converter = None

    @classmethod
    def get_converters(cls):
        if cls._converters is None:
            from converters.markitdown_converter import MarkItDownConverter
            markitdown = MarkItDownConverter()
            cls._converters = {
                '.pdf': PDFConverter(),
                '.docx': markitdown,
                '.doc': markitdown,
                '.xlsx': markitdown,
                '.xls': markitdown,
                '.pptx': markitdown,
                '.ppt': markitdown,
                '.html': markitdown,
                '.htm': markitdown,
                '.txt': markitdown,
            }
        return cls._converters

    @classmethod
    def get_reverse_converter(cls):
        if cls._reverse_converter is None:
            from md_reverse.to_document import MarkdownToDocument
            cls._reverse_converter = MarkdownToDocument()
        return cls._reverse_converter

    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {format % args}")

    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            data = json.loads(body.decode('utf-8'))
            result = self.process_conversion(data)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(result, ensure_ascii=False).encode('utf-8'))
        except Exception as e:
            error_result = {'success': False, 'error': str(e)}
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(error_result, ensure_ascii=False).encode('utf-8'))

    def do_GET(self):
        ocr_status = 'unknown'
        pdf_converter = self.get_converters().get('.pdf')
        if pdf_converter and hasattr(pdf_converter, 'ocr') and pdf_converter.ocr:
            ocr_status = 'available' if pdf_converter.ocr.available else 'unavailable'
        elif pdf_converter and pdf_converter.ocr is False:
            ocr_status = 'unavailable'

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({
            'status': 'ok',
            'ocr': ocr_status
        }).encode())

    def process_conversion(self, data):
        file_path = data.get('filePath')
        target_format = data.get('targetFormat', 'md')

        if not file_path or not os.path.exists(file_path):
            return {'success': False, 'error': f'文件不存在: {file_path}'}

        REVERSE_TARGETS = {'docx': 'to_docx', 'pptx': 'to_pptx', 'html': 'to_html', 'pdf': 'to_pdf'}

        output_dir = data.get('outputDir') or os.path.dirname(file_path)
        ext = os.path.splitext(file_path)[1].lower()

        # 反向转换：Markdown -> 其他格式
        if ext == '.md' and target_format in REVERSE_TARGETS:
            return self._reverse_convert(file_path, target_format, output_dir)

        if ext not in self.get_converters() and ext != '.md':
            return {'success': False, 'error': f'不支持的文件格式: {ext}'}

        # 正向转换：文档 -> Markdown
        if target_format != 'md':
            return {'success': False, 'error': f'仅支持转换为 Markdown 格式'}

        try:
            return self.convert_to_markdown(file_path, ext, output_dir)
        except Exception as e:
            import traceback
            traceback.print_exc()
            return {'success': False, 'error': f'转换失败: {str(e)}'}

    def _reverse_convert(self, file_path, target_format, output_dir):
        """反向转换：Markdown -> DOCX/PPTX/HTML/PDF"""
        REVERSE_MAP = {
            'docx': self.get_reverse_converter().to_docx,
            'pptx': self.get_reverse_converter().to_pptx,
            'html': self.get_reverse_converter().to_html,
            'pdf': self.get_reverse_converter().to_pdf,
        }
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                md_text = f.read()

            os.makedirs(output_dir, exist_ok=True)
            base_name = os.path.splitext(os.path.basename(file_path))[0]
            output_path = os.path.join(output_dir, f'{base_name}.{target_format}')

            REVERSE_MAP[target_format](md_text, output_path)

            return {'success': True, 'outputPath': output_path}
        except Exception as e:
            import traceback
            traceback.print_exc()
            return {'success': False, 'error': f'反向转换失败: {str(e)}'}

    def convert_to_markdown(self, file_path, ext, output_dir):
        converter = self.get_converters().get(ext)
        if not converter:
            return {'success': False, 'error': f'不支持的格式: {ext}'}

        os.makedirs(output_dir, exist_ok=True)
        base_name = os.path.splitext(os.path.basename(file_path))[0]
        output_path = os.path.join(output_dir, base_name + '.md')

        markdown_content = converter.to_markdown(file_path, output_dir)

        # Extract embedded images from the source document
        image_map = self._extract_images(file_path, ext, output_dir)
        if image_map:
            image_lines = ['\n\n---\n\n## Extracted Images\n']
            for _, saved_filename in image_map.items():
                image_lines.append(f'\n![image](images/{saved_filename})\n')
            markdown_content += ''.join(image_lines)

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(markdown_content)

        return {'success': True, 'outputPath': output_path, 'content': markdown_content}

    def _extract_images(self, file_path, ext, output_dir):
        """Dispatch to the appropriate ImageExtractor method based on file extension."""
        try:
            from utils.image_extractor import ImageExtractor
            if ext == '.pdf':
                return ImageExtractor.extract_from_pdf(file_path, output_dir)
            elif ext == '.docx':
                return ImageExtractor.extract_from_docx(file_path, output_dir)
            elif ext == '.pptx':
                return ImageExtractor.extract_from_pptx(file_path, output_dir)
        except Exception:
            pass
        return {}


def run_server(port=8765):
    server = HTTPServer(('127.0.0.1', port), ConversionHandler)
    print(f'Python conversion service running on port {port}')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    run_server(port)