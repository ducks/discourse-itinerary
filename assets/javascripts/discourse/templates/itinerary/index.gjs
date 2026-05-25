import TripList from "../../components/trip-list";

<template>
  <div class="container itinerary-page">
    <TripList @trips={{@model.trips}} />
  </div>
</template>
