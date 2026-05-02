async function deploy(image) {
  const agentUrl = document.getElementById('agentUrl').value;
  const statusId = image.includes('php') ? 'php-status' : 'httpd-status';
  const status = document.getElementById(statusId);

  status.textContent = "🚀 Deploying...";

  try {
    const res = await fetch(`${agentUrl}/deploy`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ image })
    });

    const data = await res.json();
    if (data.ip && data.port) {
      status.textContent = `✅ Running at http://${data.ip}:${data.port}`;
    } else {
      status.textContent = "❌ Deployment failed.";
    }
  } catch (e) {
    status.textContent = "❌ Network error.";
  }
}
