import TripTimeline from "../../components/trip-timeline";

<template>
  <div class="container itinerary-page">
    <TripTimeline @trip={{@model.trip}} @items={{@model.items}} />
  </div>
</template>
