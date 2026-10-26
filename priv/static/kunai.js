// Kunai's pages in the browser: copying a value (`kunai:copy`, from
// Kunai.Components.copy/1). Import it in the app's JavaScript:
//
//     import "../../deps/kunai/priv/static/kunai.js"
//
// The copy buttons show once it runs.
(() => {
  if (typeof window === "undefined" || window.__kunai) return
  window.__kunai = true
  document.documentElement.classList.add("kunai-js")

  window.addEventListener("kunai:copy", (event) => {
    const button = event.target
    const value = button.dataset.copy
    if (value == null || !navigator.clipboard) return

    navigator.clipboard.writeText(value).then(() => {
      button.dataset.copied = ""
      clearTimeout(button.__kunaiCopied)
      button.__kunaiCopied = setTimeout(() => delete button.dataset.copied, 1600)
    })
  })
})()
