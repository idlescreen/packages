// install.js — tab switching + copy-to-clipboard for install commands
function switchTab(type) {
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

    document.getElementById(type + '-tab').classList.add('active');
    document.getElementById(type + '-content').classList.add('active');
}

function copyCommand(id, btn) {
    const cmdText = document.getElementById(id).textContent;
    navigator.clipboard.writeText(cmdText).then(() => {
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        btn.style.background = '#10b981';
        btn.style.boxShadow = '0 4px 12px rgba(16, 185, 129, 0.2)';

        setTimeout(() => {
            btn.textContent = originalText;
            btn.style.background = 'var(--accent-primary)';
            btn.style.boxShadow = '0 4px 12px rgba(255, 133, 65, 0.25)';
        }, 2000);
    }).catch(err => {
        console.error('Could not copy text: ', err);
    });
}
