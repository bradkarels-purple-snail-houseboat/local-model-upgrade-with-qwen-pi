---
layout: default
---

{% include_relative README.md %}

<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
  document.querySelectorAll('code.language-mermaid').forEach(function (codeEl) {
    var pre = document.createElement('pre');
    pre.className = 'mermaid';
    pre.textContent = codeEl.textContent;
    codeEl.parentElement.replaceWith(pre);
  });
  mermaid.initialize({ startOnLoad: true, theme: 'neutral' });
</script>
