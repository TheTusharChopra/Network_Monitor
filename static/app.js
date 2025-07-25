const { useState, useEffect, Component } = React;

// Error boundary to catch render errors
class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true };
  }

  render() {
    if (this.state.hasError) {
      return React.createElement('div', {
        className: 'bg-red-100 text-red-700 p-4 rounded mb-4'
      }, 'Error rendering devices. Check console for details.');
    }
    return this.props.children;
  }
}

const LOCAL_USERNAME = 'sspl';
const LOCAL_PASSWORD = 'password';

const Login = ({ onLogin }) => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = (e) => {
    e.preventDefault();
    if (username === LOCAL_USERNAME && password === LOCAL_PASSWORD) {
      localStorage.setItem('sspl_logged_in', 'true');
      onLogin();
    } else {
      setError('Invalid username or password');
    }
  };

  return React.createElement('div', { className: 'min-h-screen flex items-center justify-center bg-gray-100' },
    React.createElement('form', {
      onSubmit: handleSubmit,
      className: 'bg-white p-8 rounded shadow-md w-full max-w-xs'
    }, [
      React.createElement('h2', { key: 'title', className: 'text-2xl font-bold mb-6 text-center text-blue-800' }, 'Login'),
      error && React.createElement('div', { key: 'error', className: 'mb-4 text-red-600 text-sm text-center' }, error),
      React.createElement('input', {
        key: 'username',
        type: 'text',
        placeholder: 'Username',
        value: username,
        onChange: e => setUsername(e.target.value),
        className: 'w-full mb-4 px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-400'
      }),
      React.createElement('input', {
        key: 'password',
        type: 'password',
        placeholder: 'Password',
        value: password,
        onChange: e => setPassword(e.target.value),
        className: 'w-full mb-6 px-3 py-2 border rounded focus:outline-none focus:ring-2 focus:ring-blue-400'
      }),
      React.createElement('button', {
        key: 'login',
        type: 'submit',
        className: 'w-full bg-blue-800 text-white py-2 rounded-lg hover:bg-blue-700 font-semibold transition-colors duration-200'
      }, 'Login')
    ])
  );
};

// Modal component for displaying logs
const LogsModal = ({ device, logs, error, onClose }) => {
  return React.createElement('div', {
    className: 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
  }, React.createElement('div', {
    className: 'bg-white rounded-lg p-6 w-full max-w-4xl max-h-[80vh] overflow-y-auto'
  }, [
    React.createElement('div', {
      key: 'header',
      className: 'flex justify-between items-center mb-4'
    }, [
      React.createElement('h2', {
        className: 'text-xl font-bold text-blue-800'
      }, `Logs for ${device.hostname || 'Unknown'}`),
      React.createElement('button', {
        onClick: onClose,
        className: 'text-gray-500 hover:text-gray-700 text-2xl'
      }, '×')
    ]),
    error && React.createElement('div', {
      key: 'error',
      className: 'bg-red-100 text-red-700 p-4 rounded mb-4'
    }, error),
    logs.length === 0 && !error ? React.createElement('div', {
      key: 'no-logs',
      className: 'text-gray-500 text-center'
    }, 'No logs available for this device.') : React.createElement('table', {
      className: 'min-w-full divide-y divide-gray-200'
    }, [
      React.createElement('thead', {
        key: 'thead',
        className: 'bg-gray-50'
      }, React.createElement('tr', null, [
        React.createElement('th', {
          className: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider'
        }, 'Time'),
        React.createElement('th', {
          className: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider'
        }, 'Source'),
        React.createElement('th', {
          className: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider'
        }, 'Event ID'),
        React.createElement('th', {
          className: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider'
        }, 'Message')
      ])),
      React.createElement('tbody', {
        key: 'tbody',
        className: 'bg-white divide-y divide-gray-200'
      }, logs.map((log, index) => React.createElement('tr', {
        key: index,
        className: 'hover:bg-gray-50'
      }, [
        React.createElement('td', {
          className: 'px-6 py-4 whitespace-nowrap text-sm text-gray-900'
        }, log.time || 'N/A'),
        React.createElement('td', {
          className: 'px-6 py-4 whitespace-nowrap text-sm text-gray-900'
        }, log.source || 'N/A'),
        React.createElement('td', {
          className: 'px-6 py-4 whitespace-nowrap text-sm text-gray-900'
        }, log.event_id || 'N/A'),
        React.createElement('td', {
          className: 'px-6 py-4 text-sm text-gray-900',
          title: log.message
        }, log.message ? (log.message.length > 50 ? log.message.slice(0, 50) + '...' : log.message) : 'N/A')
      ])))
    ])
  ]));
};

const App = () => {
  const [devices, setDevices] = useState([]);
  const [sortConfig, setSortConfig] = useState({ key: 'hostname', direction: 'ascending' });
  const [error, setError] = useState(null);
  const [loggedIn, setLoggedIn] = useState(localStorage.getItem('sspl_logged_in') === 'true');
  const [selectedDevice, setSelectedDevice] = useState(null);
  const [deviceLogs, setDeviceLogs] = useState([]);
  const [logsError, setLogsError] = useState(null);

  const handleLogin = () => setLoggedIn(true);
  const handleLogout = () => {
    localStorage.removeItem('sspl_logged_in');
    setLoggedIn(false);
  };

  // Fetch devices
  const fetchDevices = async () => {
    try {
      const response = await fetch('/devices');
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log('Fetched devices:', data);
      setDevices(Array.isArray(data) ? data : []);
      setError(null);
    } catch (err) {
      setError(`Error fetching devices: ${err.message}`);
      console.error('Fetch error:', err);
    }
  };

  // Fetch logs for a specific device
  const fetchDeviceLogs = async (hostname) => {
    try {
      const response = await fetch(`/devices/logs/${encodeURIComponent(hostname)}`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      console.log(`Fetched logs for ${hostname}:`, data.logs);
      setDeviceLogs(Array.isArray(data.logs) ? data.logs : []);
      setLogsError(null);
    } catch (err) {
      setLogsError(`Error fetching logs: ${err.message}`);
      console.error('Fetch logs error:', err);
      setDeviceLogs([]);
    }
  };

  // Open logs modal
  const openLogsModal = (device) => {
    setSelectedDevice(device);
    fetchDeviceLogs(device.hostname);
  };

  // Close logs modal
  const closeLogsModal = () => {
    setSelectedDevice(null);
    setDeviceLogs([]);
    setLogsError(null);
  };

  // Sort devices
  const requestSort = (key) => {
    let direction = 'ascending';
    if (sortConfig.key === key && sortConfig.direction === 'ascending') {
      direction = 'descending';
    }
    setSortConfig({ key, direction });
  };

  const sortedDevices = [...devices].sort((a, b) => {
    const aValue = a[sortConfig.key] || '';
    const bValue = b[sortConfig.key] || '';
    if (aValue < bValue) return sortConfig.direction === 'ascending' ? -1 : 1;
    if (aValue > bValue) return sortConfig.direction === 'ascending' ? 1 : -1;
    return 0;
  });

  useEffect(() => {
    if (loggedIn) {
      fetchDevices();
      const interval = setInterval(fetchDevices, 60000);
      return () => clearInterval(interval);
    }
  }, [loggedIn]);

  const columns = [
    { key: 'hostname', label: 'Hostname' },
    { key: 'ip_address', label: 'IP Address' },
    { key: 'mac_address', label: 'MAC Address' },
    { key: 'os', label: 'OS' },
    { key: 'cpu', label: 'CPU' },
    { key: 'memory_total', label: 'Memory (GB)' },
    { key: 'serial_number', label: 'Serial Number' },
    { key: 'hwid', label: 'HWID' },
    { key: 'bios_version', label: 'BIOS Version' },
    { key: 'installed_software', label: 'Installed Software' }
  ];

  function deviceToCSV(device) {
    const keys = Object.keys(device);
    const values = keys.map(k => {
      let v = device[k];
      if (k === 'disks' && Array.isArray(v)) {
        return '"' + v.map(disk => `${disk.device}:${disk.model}:${disk.size}x`).join('; ') + '"';
      }
      if (k === 'installed_software' && Array.isArray(v)) {
        return '"' + v.join('; ') + '"';
      }
      if (Array.isArray(v)) return '"' + v.join('; ') + '"';
      if (typeof v === 'object' && v !== null) return '"' + JSON.stringify(v) + '"';
      return '"' + String(v).replace(/"/g, '""') + '"';
    });
    return keys.join(',') + '\n' + values.join(',');
  }

  function downloadCSV(device) {
    const csv = deviceToCSV(device);
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = (device.hostname || 'device') + '.csv';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  function downloadPDF(device) {
    const doc = window.jspdf ? new window.jspdf.jsPDF() : null;
    if (!doc) {
      alert('PDF library not loaded. Please ensure jspdf.umd.min.js is available.');
      return;
    }
    let y = 10;
    doc.setFontSize(14);
    doc.text('Device Data', 10, y);
    y += 10;
    doc.setFontSize(10);
    Object.entries(device).forEach(([key, value]) => {
      let val = value;
      if (key === 'disks' && Array.isArray(val)) {
        doc.text(`${key}:`, 10, y);
        y += 7;
        val.forEach((disk, idx) => {
          const diskStr = `  - ${disk.device}:${disk.model}:${disk.size}x`;
          doc.text(diskStr, 14, y);
          y += 7;
          if (y > 280) { doc.addPage(); y = 10; }
        });
        return;
      }
      if (key === 'installed_software' && Array.isArray(val)) {
        doc.text(`${key}:`, 10, y);
        y += 7;
        val.forEach((software, idx) => {
          doc.text(`  - ${software}`, 14, y, { maxWidth: 180 });
          y += 7;
          if (y > 280) { doc.addPage(); y = 10; }
        });
        return;
      }
      if (Array.isArray(val)) val = val.join(', ');
      if (typeof val === 'object' && val !== null) val = JSON.stringify(val);
      const lines = doc.splitTextToSize(`${key}: ${val}`, 180);
      lines.forEach(line => {
        doc.text(line, 10, y);
        y += 7;
        if (y > 280) { doc.addPage(); y = 10; }
      });
    });
    doc.save((device.hostname || 'device') + '.pdf');
  }

  // Download logs JSON for a device
  const downloadDeviceLogs = async (device) => {
    try {
      const response = await fetch(`/devices/logs/${device.ip_address}`);
      if (!response.ok) {
        alert(`Failed to fetch logs: HTTP ${response.status}`);
        return;
      }
      const data = await response.json();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${device.hostname || device.ip_address || 'device'}_logs.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err) {
      alert(`Error downloading logs: ${err.message}`);
    }
  };

  const renderTableHeader = () => {
    return React.createElement('tr', null,
      columns.map(({ key, label }) =>
        React.createElement('th', {
          key,
          onClick: () => requestSort(key),
          className: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100'
        }, [
          label,
          sortConfig.key === key && React.createElement('span', null,
            sortConfig.direction === 'ascending' ? ' ↑' : ' ↓'
          )
        ])
      ).concat(
        React.createElement('th', {
          key: 'actions',
          className: 'px-6 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider'
        }, 'Actions')
      )
    );
  };

  const renderTableBody = () => {
    if (sortedDevices.length === 0) {
      return React.createElement('tr', null,
        React.createElement('td', {
          colSpan: columns.length + 1,
          className: 'px-6 py-4 text-center text-gray-500'
        }, 'No devices found. Run agents on slaves to collect data.')
      );
    }
    return sortedDevices.map((device, index) =>
      React.createElement('tr', {
        key: index,
        className: 'hover:bg-gray-50'
      }, [
        ...columns.map(({ key }) => {
          let content;
          if (key === 'installed_software' && Array.isArray(device[key])) {
            content = device[key].slice(0, 5).join(', ') + (device[key].length > 5 ? '...' : '');
          } else {
            content = device[key] || 'N/A';
          }
          return React.createElement('td', {
            key,
            className: 'px-6 py-4 whitespace-nowrap text-sm text-gray-900',
            title: key === 'installed_software' && Array.isArray(device[key]) ? device[key].join('\n') : undefined
          }, content);
        }),
        React.createElement('td', {
          key: 'actions',
          className: 'px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-center'
        }, [
          React.createElement('button', {
            key: 'logs',
            className: 'bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded mr-2',
            onClick: () => downloadDeviceLogs(device)
          }, 'View Logs'),
          React.createElement('button', {
            key: 'csv',
            className: 'bg-green-600 hover:bg-green-700 text-white px-3 py-1 rounded mr-2',
            onClick: () => downloadCSV(device)
          }, 'Download CSV'),
          React.createElement('button', {
            key: 'pdf',
            className: 'bg-blue-700 hover:bg-blue-800 text-white px-3 py-1 rounded',
            onClick: () => downloadPDF(device)
          }, 'Download PDF')
        ])
      ])
    );
  };

  if (!loggedIn) {
    return React.createElement(Login, { onLogin: handleLogin });
  }

  return React.createElement(ErrorBoundary, null,
    React.createElement('div', {
      className: 'min-h-screen bg-gray-100'
    }, [
      React.createElement('header', {
        key: 'header',
        className: 'bg-blue-800 text-white py-6 shadow-lg'
      }, [
        React.createElement('h1', {
          key: 'title',
          className: 'text-3xl font-bold text-center'
        }, 'SSPL Central Network Monitoring System'),
        React.createElement('div', {
          key: 'logo',
          className: 'flex justify-center my-4'
        }, React.createElement('img', {
          src: '/static/drdo_logo.png',
          alt: 'DRDO Logo',
          className: 'h-20',
          onError: (e) => { e.target.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYAAAAAIAAFl4e8gAAAAASUVORK5CYII='; }
        })),
        React.createElement('button', {
          key: 'logout',
          onClick: handleLogout,
          className: 'absolute top-6 right-6 bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded font-semibold transition-colors duration-200'
        }, 'Logout')
      ]),
      React.createElement('main', {
        key: 'main',
        className: 'container mx-auto p-6'
      }, [
        error && React.createElement('div', {
          key: 'error',
          className: 'bg-red-100 text-red-700 p-4 rounded mb-4'
        }, error),
        React.createElement('div', {
          key: 'table-container',
          className: 'bg-white shadow-md rounded-lg overflow-x-auto'
        }, React.createElement('table', {
          className: 'min-w-full divide-y divide-gray-200'
        }, [
          React.createElement('thead', {
            key: 'thead',
            className: 'bg-gray-50'
          }, renderTableHeader()),
          React.createElement('tbody', {
            key: 'tbody',
            className: 'bg-white divide-y divide-gray-200'
          }, renderTableBody())
        ])),
        React.createElement('div', {
          key: 'download-links',
          className: 'mt-4 text-gray-600 text-sm'
        }, [
          'Download agents: ',
          React.createElement('a', {
            key: 'windows-ps1',
            href: '/download/windows',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Windows (.ps1)'),
          ' | ',
          React.createElement('a', {
            key: 'windows-bat',
            href: '/download/windows-bat',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Windows (.bat)'),
          ' | ',
          React.createElement('a', {
            key: 'windows-proxy-ps1',
            href: '/download/windows-proxy',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Windows Proxy (.ps1)'),
          ' | ',
          React.createElement('a', {
            key: 'windows-proxy-bat',
            href: '/download/windows-proxy-bat',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Windows Proxy (.bat)'),
          ' | ',
          React.createElement('a', {
            key: 'linux',
            href: '/download/linux',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Linux'),
          React.createElement('br', { key: 'br1' }),
          'Clear USB History: ',
          React.createElement('a', {
            key: 'clear-usb-windows',
            href: '/download/clear_usb_history_windows',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Windows'),
          ' | ',
          React.createElement('a', {
            key: 'clear-usb-linux',
            href: '/download/clear_usb_history_linux',
            className: 'text-blue-500 hover:underline ml-2'
          }, 'Linux')
        ]),
        selectedDevice && React.createElement(LogsModal, {
          key: 'logs-modal',
          device: selectedDevice,
          logs: deviceLogs,
          error: logsError,
          onClose: closeLogsModal
        })
      ])
    ])
  );
};

ReactDOM.render(
  React.createElement(App),
  document.getElementById('root')
);