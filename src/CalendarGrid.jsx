import React from 'react'
import FullCalendar from '@fullcalendar/react'
import dayGridPlugin from '@fullcalendar/daygrid'
import timeGridPlugin from '@fullcalendar/timegrid'
import './eventCalendar.css'

export default function CalendarGrid({ events, items, owner, canAdmin, edit, onRangeChange }) {
    return <FullCalendar
        plugins={[dayGridPlugin, timeGridPlugin]}
        initialView="timeGridWeek"
        headerToolbar={{ left: 'prev,next today', center: 'title', right: 'dayGridMonth,timeGridWeek,timeGridDay' }}
        events={events}
        height="auto"
        nowIndicator
        dayMaxEvents
        scrollTime="07:00:00"
        eventTimeFormat={{ hour: 'numeric', minute: '2-digit' }}
        datesSet={({ startStr, endStr }) => onRangeChange({ start: startStr, end: endStr })}
        eventClick={({ event }) => { const item = items.find((record) => record.id === event.id); if (item && (owner || canAdmin)) edit(item) }}
        eventContent={({ timeText, event }) => <div className="event-calendar-entry"><span>{timeText}</span><strong>{event.title}</strong>{event.extendedProps.location && <small>{event.extendedProps.location}</small>}{event.extendedProps.repeatLabel && <small>{event.extendedProps.repeatLabel}</small>}</div>}
        noEventsContent="No events in this view"
    />
}