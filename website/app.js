/* TRACKLIFTS — site interactions: scroll reveal, sticky nav, count-ups, menu. */
(function () {
  'use strict';

  /* Sticky nav: solidify on scroll */
  const nav = document.querySelector('.site-nav');
  const onScroll = () => {
    if (!nav) return;
    nav.classList.toggle('scrolled', window.scrollY > 12);
  };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  /* Mobile nav toggle */
  const toggle = document.querySelector('.nav-toggle');
  if (toggle && nav) {
    toggle.addEventListener('click', () => nav.classList.toggle('open'));
    nav.querySelectorAll('.nav-links a').forEach((a) =>
      a.addEventListener('click', () => nav.classList.remove('open'))
    );
  }

  /* Reveal on scroll */
  const reveals = document.querySelectorAll('[data-reveal]');
  if ('IntersectionObserver' in window && reveals.length) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add('in');
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: '0px 0px -8% 0px' }
    );
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('in'));
  }

  /* Count-up for [data-count] numbers when they scroll into view */
  const fmt = (n) => n.toLocaleString('en-US');
  const counters = document.querySelectorAll('[data-count]');
  const animate = (el) => {
    const target = parseFloat(el.getAttribute('data-count'));
    const suffix = el.getAttribute('data-suffix') || '';
    const dur = 1400;
    const start = performance.now();
    const step = (now) => {
      const t = Math.min((now - start) / dur, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      const val = Math.round(target * eased);
      el.textContent = fmt(val) + suffix;
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  };
  if ('IntersectionObserver' in window && counters.length) {
    const cio = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            animate(e.target);
            cio.unobserve(e.target);
          }
        });
      },
      { threshold: 0.5 }
    );
    counters.forEach((el) => cio.observe(el));
  }

  /* Subtle pointer-parallax for elements with [data-parallax] (depth = factor) */
  const parallax = document.querySelectorAll('[data-parallax]');
  if (parallax.length && window.matchMedia('(pointer:fine)').matches) {
    window.addEventListener('mousemove', (e) => {
      const cx = (e.clientX / window.innerWidth - 0.5);
      const cy = (e.clientY / window.innerHeight - 0.5);
      parallax.forEach((el) => {
        const d = parseFloat(el.getAttribute('data-parallax')) || 12;
        el.style.transform = `translate(${cx * d}px, ${cy * d}px)`;
      });
    }, { passive: true });
  }

  /* Active nav link by current path */
  const here = location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav-links a').forEach((a) => {
    const href = (a.getAttribute('href') || '').split('/').pop();
    if (href === here) a.classList.add('active');
  });

  /* Current year in footer */
  document.querySelectorAll('[data-year]').forEach((el) => {
    el.textContent = new Date().getFullYear();
  });
})();
