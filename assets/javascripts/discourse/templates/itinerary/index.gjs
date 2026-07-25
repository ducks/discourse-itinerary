import TripList from "../../components/trip-list";

<template>
  <div class="container itinerary-page">
    <TripList @trips={{@model.trips}} @meta={{@model.meta}} />
  </div>
</template>
