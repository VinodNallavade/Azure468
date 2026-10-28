document.addEventListener("DOMContentLoaded", () => {
  const printButton = document.querySelector("#print-resume");
  printButton?.addEventListener("click", () => window.print());
});
