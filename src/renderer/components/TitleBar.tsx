export default function TitleBar() {
  const isMac = window.electronAPI?.isMac

  const handleMinimize = () => {
    window.electronAPI?.minimize()
  }

  const handleMaximize = () => {
    window.electronAPI?.maximize()
  }

  const handleClose = () => {
    window.electronAPI?.close()
  }

  return (
    <div className="title-bar">
      <div className={`title-bar-drag${isMac ? ' mac' : ''}`}>MarkAny</div>
      {!isMac && (
        <div className="title-bar-controls">
          <button className="title-btn minimize" onClick={handleMinimize}>─</button>
          <button className="title-btn maximize" onClick={handleMaximize}>□</button>
          <button className="title-btn close" onClick={handleClose}>✕</button>
        </div>
      )}
    </div>
  )
}
