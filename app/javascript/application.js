// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "./dns_leak_test"

// Only load conversion optimizer on CRO landing page
document.addEventListener('DOMContentLoaded', function() {
  // Check if we're on the CRO landing page by looking for the cro parameter or specific CRO elements
  const urlParams = new URLSearchParams(window.location.search);
  const isCROPage = urlParams.has('cro') || document.querySelector('#offer-countdown');
  
  if (isCROPage) {
    import("./conversion_optimizer").then(module => {
      console.log('CRO optimizations loaded');
    });
  }
});
