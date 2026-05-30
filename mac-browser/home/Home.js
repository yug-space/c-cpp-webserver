const query = document.getElementById("query");
const openButton = document.getElementById("open");
const deepButton = document.getElementById("deep-search");

function encodedValue() {
  return encodeURIComponent(query.value.trim());
}

function openInput(value = query.value.trim()) {
  if (!value) return;
  window.location.href = `trailbrowser://open?input=${encodeURIComponent(value)}`;
}

function deepSearch() {
  const value = encodedValue();
  if (!value) return;
  window.location.href = `trailbrowser://deep-search?q=${value}`;
}

openButton.addEventListener("click", () => openInput());
deepButton.addEventListener("click", deepSearch);

query.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") return;
  event.preventDefault();
  if (event.shiftKey) {
    deepSearch();
  } else {
    openInput();
  }
});

document.querySelectorAll("[data-open]").forEach((button) => {
  button.addEventListener("click", () => openInput(button.dataset.open));
});
