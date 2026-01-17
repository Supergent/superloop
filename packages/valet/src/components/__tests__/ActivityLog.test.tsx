import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ActivityLog, ActivityLogEntry } from '../ActivityLog';

describe('ActivityLog', () => {
  const mockEntries: ActivityLogEntry[] = [
    {
      id: '1',
      timestamp: Date.now() - 5000, // 5 seconds ago
      type: 'clean',
      description: 'Cleaned system cache',
      details: 'Recovered 2.5 GB',
    },
    {
      id: '2',
      timestamp: Date.now() - 120000, // 2 minutes ago
      type: 'optimize',
      description: 'Optimized system performance',
    },
    {
      id: '3',
      timestamp: Date.now() - 3600000, // 1 hour ago
      type: 'scan',
      description: 'System health check',
      details: 'No issues found',
    },
    {
      id: '4',
      timestamp: Date.now() - 86400000, // 1 day ago
      type: 'uninstall',
      description: 'Uninstalled Slack',
      details: 'Recovered 500 MB',
    },
    {
      id: '5',
      timestamp: Date.now() - 172800000, // 2 days ago
      type: 'other',
      description: 'General maintenance',
    },
  ];

  let realNow: number;

  beforeEach(() => {
    realNow = Date.now();
    vi.spyOn(Date, 'now').mockReturnValue(realNow);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('should render empty state when no entries provided', () => {
    render(<ActivityLog entries={[]} />);

    expect(screen.getByText('No recent activity')).toBeInTheDocument();
    expect(screen.getByText('No recent activity').closest('.activity-log')).toHaveClass('empty');
  });

  it('should render all entries when fewer than maxEntries', () => {
    const threeEntries = mockEntries.slice(0, 3);
    render(<ActivityLog entries={threeEntries} />);

    expect(screen.getByText('Cleaned system cache')).toBeInTheDocument();
    expect(screen.getByText('Optimized system performance')).toBeInTheDocument();
    expect(screen.getByText('System health check')).toBeInTheDocument();
  });

  it('should limit entries to maxEntries prop', () => {
    render(<ActivityLog entries={mockEntries} maxEntries={3} />);

    expect(screen.getByText('Cleaned system cache')).toBeInTheDocument();
    expect(screen.getByText('Optimized system performance')).toBeInTheDocument();
    expect(screen.getByText('System health check')).toBeInTheDocument();
    expect(screen.queryByText('Uninstalled Slack')).not.toBeInTheDocument();
    expect(screen.queryByText('General maintenance')).not.toBeInTheDocument();
  });

  it('should default to 5 entries when maxEntries not specified', () => {
    const sixEntries: ActivityLogEntry[] = [
      ...mockEntries,
      {
        id: '6',
        timestamp: Date.now() - 259200000, // 3 days ago
        type: 'clean',
        description: 'Should not appear',
      },
    ];

    render(<ActivityLog entries={sixEntries} />);

    expect(screen.queryByText('Should not appear')).not.toBeInTheDocument();
  });

  it('should display details when provided', () => {
    render(<ActivityLog entries={mockEntries} />);

    expect(screen.getByText('Recovered 2.5 GB')).toBeInTheDocument();
    expect(screen.getByText('No issues found')).toBeInTheDocument();
  });

  it('should not display details section when details not provided', () => {
    render(<ActivityLog entries={mockEntries} />);

    const optimizeEntry = screen.getByText('Optimized system performance').parentElement?.parentElement;
    expect(optimizeEntry?.querySelector('.activity-details')).not.toBeInTheDocument();
  });

  it('should display correct icon for each activity type', () => {
    render(<ActivityLog entries={mockEntries} />);

    const entries = screen.getAllByRole('generic').filter((el) => el.className === 'activity-entry');

    expect(entries[0].querySelector('.activity-icon')?.textContent).toBe('🧹'); // clean
    expect(entries[1].querySelector('.activity-icon')?.textContent).toBe('⚡'); // optimize
    expect(entries[2].querySelector('.activity-icon')?.textContent).toBe('🔍'); // scan
    expect(entries[3].querySelector('.activity-icon')?.textContent).toBe('🗑️'); // uninstall
    expect(entries[4].querySelector('.activity-icon')?.textContent).toBe('📋'); // other
  });

  it('should format timestamp as "Just now" for very recent activities', () => {
    const recentEntry: ActivityLogEntry = {
      id: '1',
      timestamp: Date.now() - 30000, // 30 seconds ago
      type: 'scan',
      description: 'Recent scan',
    };

    render(<ActivityLog entries={[recentEntry]} />);

    expect(screen.getByText('Just now')).toBeInTheDocument();
  });

  it('should format timestamp in minutes for activities within last hour', () => {
    const minuteEntry: ActivityLogEntry = {
      id: '1',
      timestamp: Date.now() - 300000, // 5 minutes ago
      type: 'clean',
      description: 'Recent clean',
    };

    render(<ActivityLog entries={[minuteEntry]} />);

    expect(screen.getByText('5m ago')).toBeInTheDocument();
  });

  it('should format timestamp in hours for activities within last day', () => {
    const hourEntry: ActivityLogEntry = {
      id: '1',
      timestamp: Date.now() - 7200000, // 2 hours ago
      type: 'optimize',
      description: 'Recent optimize',
    };

    render(<ActivityLog entries={[hourEntry]} />);

    expect(screen.getByText('2h ago')).toBeInTheDocument();
  });

  it('should format timestamp in days for older activities', () => {
    const dayEntry: ActivityLogEntry = {
      id: '1',
      timestamp: Date.now() - 259200000, // 3 days ago
      type: 'uninstall',
      description: 'Old uninstall',
    };

    render(<ActivityLog entries={[dayEntry]} />);

    expect(screen.getByText('3d ago')).toBeInTheDocument();
  });

  it('should render entries with unique keys', () => {
    const { container } = render(<ActivityLog entries={mockEntries} />);

    const entries = container.querySelectorAll('.activity-entry');
    expect(entries).toHaveLength(5);

    // Check that each entry has a unique key by verifying they all render
    mockEntries.forEach((entry) => {
      expect(screen.getByText(entry.description)).toBeInTheDocument();
    });
  });

  it('should maintain entry order', () => {
    render(<ActivityLog entries={mockEntries} />);

    const descriptions = screen.getAllByRole('generic')
      .filter((el) => el.className === 'activity-description')
      .map((el) => el.textContent);

    expect(descriptions).toEqual([
      'Cleaned system cache',
      'Optimized system performance',
      'System health check',
      'Uninstalled Slack',
      'General maintenance',
    ]);
  });

  it('should apply correct CSS classes to structure', () => {
    const { container } = render(<ActivityLog entries={mockEntries.slice(0, 1)} />);

    expect(container.querySelector('.activity-log')).toBeInTheDocument();
    expect(container.querySelector('.activity-entry')).toBeInTheDocument();
    expect(container.querySelector('.activity-icon')).toBeInTheDocument();
    expect(container.querySelector('.activity-content')).toBeInTheDocument();
    expect(container.querySelector('.activity-description')).toBeInTheDocument();
    expect(container.querySelector('.activity-details')).toBeInTheDocument();
    expect(container.querySelector('.activity-time')).toBeInTheDocument();
  });
});
