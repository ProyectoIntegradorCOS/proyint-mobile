package com.example.flutter_application_1.navigation

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.common.MapboxOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapView
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.navigation.base.ExperimentalPreviewMapboxNavigationAPI
import com.mapbox.navigation.base.extensions.applyDefaultNavigationOptions
import com.mapbox.navigation.base.options.NavigationOptions
import com.mapbox.navigation.base.route.NavigationRoute
import com.mapbox.navigation.base.route.NavigationRouterCallback
import com.mapbox.navigation.base.route.RouterFailure
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.lifecycle.MapboxNavigationApp
import com.mapbox.navigation.core.lifecycle.MapboxNavigationObserver
import com.mapbox.navigation.core.trip.session.LocationMatcherResult
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.directions.session.RoutesObserver
import com.mapbox.navigation.core.lifecycle.requireMapboxNavigation
import com.mapbox.navigation.ui.maps.camera.NavigationCamera
import com.mapbox.navigation.ui.maps.camera.data.MapboxNavigationViewportDataSource
import com.mapbox.navigation.ui.maps.location.NavigationLocationProvider
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineApi
import com.mapbox.navigation.ui.maps.route.line.api.MapboxRouteLineView
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineApiOptions
import com.mapbox.navigation.ui.maps.route.line.model.MapboxRouteLineViewOptions

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Pantalla nativa de navegación (Android) usando Mapbox Navigation SDK v3 (online), reroute sí, sin voz][obj: NavigationActivity]
class NavigationActivity : ComponentActivity() {
  companion object {
    const val EXTRA_ACCESS_TOKEN = "access_token"
    const val EXTRA_PROFILE = "profile"
    const val EXTRA_WAYPOINTS = "waypoints"
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Acción broadcast para actualizar ruta en caliente (re-requestRoutes) desde Flutter][obj: NavigationActivity.ACTION_UPDATE_ROUTE]
    const val ACTION_UPDATE_ROUTE = "pe.gob.onp.thaqhiri.NAV_UPDATE_ROUTE"

    fun buildIntent(
      activity: Activity,
      accessToken: String,
      profile: String,
      waypoints: ArrayList<HashMap<String, Double>>,
    ): Intent {
      return Intent(activity, NavigationActivity::class.java).apply {
        putExtra(EXTRA_ACCESS_TOKEN, accessToken)
        putExtra(EXTRA_PROFILE, profile)
        putExtra(EXTRA_WAYPOINTS, waypoints)
      }
    }
  }

  private lateinit var mapView: MapView
  private lateinit var viewportDataSource: MapboxNavigationViewportDataSource
  private lateinit var navigationCamera: NavigationCamera
  private lateinit var routeLineApi: MapboxRouteLineApi
  private lateinit var routeLineView: MapboxRouteLineView
  private val navigationLocationProvider = NavigationLocationProvider()
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 17:05 UTC-5 (Lima)][desc: Coordina render del route line con el lifecycle del style (evita 'no se ve la ruta' si llega antes de cargar el style)][obj: NavigationActivity styleReady/lastRoutes]
  private var styleReady: Boolean = false
  private var lastRoutes: List<NavigationRoute> = emptyList()

  private var accessToken: String = ""
  private var profile: String = "walking"
  private var waypoints: MutableList<Point> = mutableListOf()
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Permite habilitar modo "agregar parada" con long-press para recalcular ruta sin salir][obj: NavigationActivity addStopMode]
  private var addStopMode: Boolean = false

  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Receiver para actualizar ruta desde Flutter via broadcast mientras la Activity está abierta][obj: NavigationActivity updateRouteReceiver]
  private val updateRouteReceiver =
    object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != ACTION_UPDATE_ROUTE) return
        val newProfile = intent.getStringExtra(EXTRA_PROFILE) ?: profile
        @Suppress("DEPRECATION")
        val raw =
          intent.getSerializableExtra(EXTRA_WAYPOINTS) as? ArrayList<HashMap<String, Double>>
            ?: arrayListOf()
        val points =
          raw.mapNotNull { m ->
            val lat = m["lat"]
            val lng = m["lng"]
            if (lat == null || lng == null) null else Point.fromLngLat(lng, lat)
          }
        if (points.size < 2) return
        profile = newProfile
        waypoints = points.toMutableList()
        Toast.makeText(this@NavigationActivity, "Actualizando ruta...", Toast.LENGTH_SHORT).show()
        requestRoute(mapboxNavigation)
      }
    }

  private val locationPermissionRequest =
    registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { permissions ->
      when {
        permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true ||
          permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true -> {
          initializeMapComponents()
        }
        else -> {
          Toast.makeText(
            this,
            "Permisos de ubicación denegados. Habilítalos en configuración.",
            Toast.LENGTH_LONG
          ).show()
          finish()
        }
      }
    }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    accessToken = intent.getStringExtra(EXTRA_ACCESS_TOKEN) ?: ""
    profile = intent.getStringExtra(EXTRA_PROFILE) ?: "walking"
    @Suppress("DEPRECATION")
    val raw = intent.getSerializableExtra(EXTRA_WAYPOINTS) as? ArrayList<HashMap<String, Double>>
      ?: arrayListOf()
    waypoints = raw.mapNotNull { m ->
      val lat = m["lat"]
      val lng = m["lng"]
      if (lat == null || lng == null) null else Point.fromLngLat(lng, lat)
    }.toMutableList()

    if (accessToken.isBlank() || waypoints.size < 2) {
      finish()
      return
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:35 UTC-5 (Lima)][desc: Define access token de Mapbox en runtime antes de inflar MapView (requerido por Mapbox SDKs)][obj: NavigationActivity.onCreate MapboxOptions.accessToken]
    MapboxOptions.accessToken = accessToken

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:30 UTC-5 (Lima)][desc: Inicializa MapboxNavigationApp antes de acceder al delegate requireMapboxNavigation (evita MapboxNavigation null)][obj: NavigationActivity.onCreate MapboxNavigationApp.setup]
    MapboxNavigationApp.setup(
      NavigationOptions.Builder(this).build()
    )

    // check/request location permissions
    if (
      ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED ||
      ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED
    ) {
      initializeMapComponents()
    } else {
      locationPermissionRequest.launch(
        arrayOf(
          Manifest.permission.ACCESS_COARSE_LOCATION,
          Manifest.permission.ACCESS_FINE_LOCATION,
        )
      )
    }
  }

  override fun onStart() {
    super.onStart()
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Registra receiver de updateRoute mientras la Activity está visible][obj: NavigationActivity.onStart registerReceiver]
    val filter = IntentFilter(ACTION_UPDATE_ROUTE)
    ContextCompat.registerReceiver(
      this,
      updateRouteReceiver,
      filter,
      ContextCompat.RECEIVER_NOT_EXPORTED,
    )
  }

  override fun onStop() {
    super.onStop()
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Desregistra receiver de updateRoute][obj: NavigationActivity.onStop unregisterReceiver]
    unregisterReceiver(updateRouteReceiver)
  }

  private fun initializeMapComponents() {
    mapView = MapView(this)
    mapView.mapboxMap.setCamera(
      CameraOptions.Builder()
        .center(waypoints.first())
        .zoom(15.0)
        .build()
    )

    mapView.location.apply {
      setLocationProvider(navigationLocationProvider)
      locationPuck = createDefault2DPuck()
      enabled = true
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:40 UTC-5 (Lima)][desc: Permite volver al app Flutter con un botón (cierra NavigationActivity)][obj: NavigationActivity close button overlay]
    val root = FrameLayout(this)
    root.addView(mapView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    val close = ImageButton(this).apply {
      setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
      setBackgroundColor(android.graphics.Color.TRANSPARENT)
      contentDescription = "Volver"
      setOnClickListener { finish() }
    }
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Botón para activar/desactivar modo agregar parada (long-press) y actualizar ruta sin salir][obj: NavigationActivity add stop button]
    val addStop = ImageButton(this).apply {
      setImageResource(android.R.drawable.ic_input_add)
      setBackgroundColor(android.graphics.Color.TRANSPARENT)
      contentDescription = "Agregar parada"
      setOnClickListener {
        addStopMode = !addStopMode
        val msg =
          if (addStopMode) "Modo agregar parada: long-press en el mapa para insertar una parada."
          else "Modo agregar parada desactivado."
        Toast.makeText(this@NavigationActivity, msg, Toast.LENGTH_SHORT).show()
      }
    }
    val sizePx = TypedValue.applyDimension(
      TypedValue.COMPLEX_UNIT_DIP,
      44f,
      resources.displayMetrics,
    ).toInt()
    val marginPx = TypedValue.applyDimension(
      TypedValue.COMPLEX_UNIT_DIP,
      12f,
      resources.displayMetrics,
    ).toInt()
    val closeParams = FrameLayout.LayoutParams(sizePx, sizePx).apply {
      gravity = Gravity.TOP or Gravity.START
      leftMargin = marginPx
      topMargin = marginPx
    }
    root.addView(close, closeParams)
    val addParams = FrameLayout.LayoutParams(sizePx, sizePx).apply {
      gravity = Gravity.TOP or Gravity.START
      leftMargin = marginPx
      topMargin = marginPx + sizePx + marginPx
    }
    root.addView(addStop, addParams)
    setContentView(root)

    viewportDataSource = MapboxNavigationViewportDataSource(mapView.mapboxMap)
    val pixelDensity = resources.displayMetrics.density
    viewportDataSource.followingPadding =
      EdgeInsets(
        180.0 * pixelDensity,
        40.0 * pixelDensity,
        150.0 * pixelDensity,
        40.0 * pixelDensity
      )

    navigationCamera = NavigationCamera(mapView.mapboxMap, mapView.camera, viewportDataSource)
    routeLineApi = MapboxRouteLineApi(MapboxRouteLineApiOptions.Builder().build())
    routeLineView = MapboxRouteLineView(MapboxRouteLineViewOptions.Builder(this).build())

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:30 UTC-5 (Lima)][desc: Carga un style compatible para navegación; sin style no se renderiza route line][obj: NavigationActivity.initializeMapComponents loadStyleUri]
    mapView.mapboxMap.loadStyleUri("mapbox://styles/mapbox/navigation-day-v1") {
      styleReady = true
      // Si la ruta llegó antes del style, fuerza render al completar el load.
      if (lastRoutes.isNotEmpty()) {
        routeLineApi.setNavigationRoutes(lastRoutes) { value ->
          mapView.mapboxMap.style?.apply {
            routeLineView.renderRouteDrawData(this, value)
          }
        }
        viewportDataSource.onRouteChanged(lastRoutes.first())
        viewportDataSource.evaluate()
        navigationCamera.requestNavigationCameraToOverview()
      }
    }

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 10:50 UTC-5 (Lima)][desc: Long-press agrega una parada antes del destino final y recalcula ruta (solo en modo addStopMode)][obj: NavigationActivity long-press add stop]
    mapView.gestures.addOnMapLongClickListener { p ->
      if (!addStopMode) return@addOnMapLongClickListener false
      if (waypoints.size < 2) return@addOnMapLongClickListener false
      if (waypoints.size >= 5) {
        Toast.makeText(this, "Máximo 5 puntos.", Toast.LENGTH_SHORT).show()
        return@addOnMapLongClickListener true
      }
      // Inserta la parada antes del último destino
      waypoints.add(waypoints.size - 1, p)
      Toast.makeText(this, "Parada agregada. Recalculando...", Toast.LENGTH_SHORT).show()
      requestRoute(mapboxNavigation)
      true
    }
  }

  private val routesObserver = RoutesObserver { routeUpdateResult ->
    if (routeUpdateResult.navigationRoutes.isNotEmpty()) {
      lastRoutes = routeUpdateResult.navigationRoutes
      if (!styleReady) return@RoutesObserver
      routeLineApi.setNavigationRoutes(routeUpdateResult.navigationRoutes) { value ->
        mapView.mapboxMap.style?.apply {
          routeLineView.renderRouteDrawData(this, value)
        }
      }

      viewportDataSource.onRouteChanged(routeUpdateResult.navigationRoutes.first())
      viewportDataSource.evaluate()
      navigationCamera.requestNavigationCameraToOverview()
    }
  }

  private val locationObserver =
    object : LocationObserver {
      override fun onNewRawLocation(rawLocation: com.mapbox.common.location.Location) {}

      override fun onNewLocationMatcherResult(locationMatcherResult: LocationMatcherResult) {
        val enhancedLocation = locationMatcherResult.enhancedLocation
        navigationLocationProvider.changePosition(
          location = enhancedLocation,
          keyPoints = locationMatcherResult.keyPoints,
        )
        viewportDataSource.onLocationChanged(enhancedLocation)
        viewportDataSource.evaluate()
        navigationCamera.requestNavigationCameraToFollowing()
      }
    }

  @OptIn(ExperimentalPreviewMapboxNavigationAPI::class)
  private val mapboxNavigation: MapboxNavigation by requireMapboxNavigation(
    onResumedObserver =
      object : MapboxNavigationObserver {
        @SuppressLint("MissingPermission")
        override fun onAttached(mapboxNavigation: MapboxNavigation) {
          mapboxNavigation.registerRoutesObserver(routesObserver)
          mapboxNavigation.registerLocationObserver(locationObserver)
          mapboxNavigation.startTripSession() // reroute automático cuando hay rutas activas
          requestRoute(mapboxNavigation)
        }

        override fun onDetached(mapboxNavigation: MapboxNavigation) {
          mapboxNavigation.unregisterRoutesObserver(routesObserver)
          mapboxNavigation.unregisterLocationObserver(locationObserver)
          mapboxNavigation.stopTripSession()
        }
      },
  )

  private fun requestRoute(mapboxNavigation: MapboxNavigation) {
    val layers = ArrayList<Int?>(waypoints.size)
    layers.add(mapboxNavigation.getZLevel())
    for (i in 1 until waypoints.size) layers.add(null)

    val routeOptions =
      RouteOptions.builder()
        .applyDefaultNavigationOptions()
        .profile(profile)
        .coordinatesList(waypoints)
        .layersList(layers)
        .build()

    mapboxNavigation.requestRoutes(
      routeOptions,
      object : NavigationRouterCallback {
        override fun onCanceled(routeOptions: RouteOptions, routerOrigin: String) {}

        override fun onFailure(reasons: List<RouterFailure>, routeOptions: RouteOptions) {
          Toast.makeText(
            this@NavigationActivity,
            "No se pudo calcular ruta (SDK).",
            Toast.LENGTH_LONG
          ).show()
          finish()
        }

        override fun onRoutesReady(routes: List<NavigationRoute>, routerOrigin: String) {
          Toast.makeText(
            this@NavigationActivity,
            "Ruta lista (${routes.size}).",
            Toast.LENGTH_SHORT
          ).show()
          mapboxNavigation.setNavigationRoutes(routes)
          navigationCamera.requestNavigationCameraToOverview()
        }
      }
    )
  }
}
