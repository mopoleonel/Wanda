# Lecture de la CNI : google_mlkit_text_recognition référence les modules de
# reconnaissance chinois, devanagari, japonais et coréen, que WANDA n'embarque
# pas (CNI camerounaise en alphabet latin). Sans ces règles, R8 bloque la
# compilation release (« Missing classes detected while running R8 »).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
