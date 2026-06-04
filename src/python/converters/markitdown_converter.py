from .base import BaseConverter, sanitize_text


def _monkeypatch_magika():
    """Inject lightweight mocks so markitdown doesn't pull in onnxruntime (~200MB)."""
    import sys
    import types

    ort = sys.modules.get('onnxruntime')
    if ort is None:
        ort = types.ModuleType('onnxruntime')
        sys.modules['onnxruntime'] = ort

    if not hasattr(ort, 'InferenceSession'):
        class _MockSession:
            def __init__(self, *a, **kw): pass
            def run(self, *a, **kw): return []
        ort.InferenceSession = _MockSession
        ort.SessionOptions = type('SessionOptions', (), {})

    mock_magika = sys.modules.get('magika')
    if mock_magika is None:
        mock_magika = types.ModuleType('magika')
        sys.modules['magika'] = mock_magika

    if not hasattr(mock_magika, 'logger'):
        mock_magika.logger = _fake_logger()
    if not hasattr(mock_magika, 'types'):
        mock_magika.types = types.ModuleType('types')

    if getattr(mock_magika, 'Magika', None) is None:
        class _MockResult:
            status = 'error'
            class _Prediction:
                class _Output:
                    mime_type = 'application/octet-stream'
                    label = 'unknown'
                output = _Output()
            prediction = _Prediction()

        class _MockMagika:
            def identify_stream(self, _stream):
                return _MockResult()
        mock_magika.Magika = _MockMagika


def _fake_logger():
    import types
    mod = types.ModuleType('logger')
    def _noop(*a, **kw): pass
    _logger = type('Logger', (), {
        'debug': _noop, 'info': _noop,
        'warning': _noop, 'error': _noop,
        'critical': _noop, 'exception': _noop,
    })()
    mod.get_logger = lambda _: _logger
    return mod


_monkeypatch_magika()
from markitdown import MarkItDown as _MarkItDown


class MarkItDownConverter(BaseConverter):
    SUPPORTED = ['.pdf', '.docx', '.doc', '.xlsx', '.xls', '.pptx', '.ppt', '.html', '.htm', '.txt']

    def get_supported_extensions(self) -> list[str]:
        return MarkItDownConverter.SUPPORTED

    def to_markdown(self, file_path: str, output_dir: str) -> str:
        md = _MarkItDown()
        result = md.convert(file_path)
        # Clean control characters (MarkItDown may still emit some)
        return sanitize_text(result.text_content)