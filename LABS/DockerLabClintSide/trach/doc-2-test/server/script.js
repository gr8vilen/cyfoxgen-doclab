async function deployContainer(apiUrl, imageName, cardId) {
  const statusEl = document.getElementById(`${cardId}-status`) || document.querySelector(`#${cardId} .status`);
  statusEl.textContent = "⏳ Deploying...";

  try {
    const res = await fetch(`${apiUrl}/deploy`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ image: imageName })
    });

    const data = await res.json();

    if (data.status === "ok") {
      statusEl.textContent = `✅ Running at ${data.ip}:${data.port}`;
    } else {
      statusEl.textContent = "❌ Deployment failed.";
    }
  } catch (err) {
    statusEl.textContent = "❌ Network error.";
    console.error(err);
  }
}
