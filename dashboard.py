import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# Configuration de la page
st.set_page_config(page_title="Reviews Dashboard", page_icon="📊", layout="wide")

# Titre
st.title("📊 Dashboard Reviews - Clothing Analytics")

# Charger les données
@st.cache_data
def load_data():
    df = pd.read_csv('data.csv')
    # Nettoyer les données
    df = df.dropna(subset=['rating', 'department_name'])
    return df

df = load_data()

# Créer les agrégations
dept_stats = df.groupby('department_name').agg({
    'review_id': 'count',
    'rating': 'mean',
    'positive_feedback_count': 'sum',
    'age': 'mean'
}).reset_index()
dept_stats.columns = ['department_name', 'total_reviews', 'avg_rating', 'total_positive_feedback', 'avg_age']

# Métriques principales
st.header("📈 Statistiques Globales")
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric("Total Reviews", f"{len(df):,}")
    
with col2:
    st.metric("Rating Moyen", f"{df['rating'].mean():.2f} ⭐")
    
with col3:
    st.metric("Feedback Positif Total", f"{df['positive_feedback_count'].sum():,.0f}")
    
with col4:
    st.metric("Âge Moyen", f"{df['age'].mean():.0f} ans")

st.divider()

# Graphiques principaux
col1, col2 = st.columns(2)

with col1:
    st.subheader("📊 Rating Moyen par Département")
    fig1 = px.bar(dept_stats.sort_values('avg_rating', ascending=False), 
                  x='department_name', 
                  y='avg_rating',
                  color='avg_rating',
                  color_continuous_scale='Blues',
                  text='avg_rating')
    fig1.update_traces(texttemplate='%{text:.2f}', textposition='outside')
    fig1.update_layout(xaxis_tickangle=-45, showlegend=False)
    st.plotly_chart(fig1, use_container_width=True)

with col2:
    st.subheader("🥧 Distribution des Reviews par Département")
    fig2 = px.pie(dept_stats, 
                  values='total_reviews', 
                  names='department_name',
                  hole=0.4)
    st.plotly_chart(fig2, use_container_width=True)

st.divider()

# Deuxième ligne de graphiques
col1, col2 = st.columns(2)

with col1:
    st.subheader("👍 Feedback Positif par Département")
    fig3 = px.bar(dept_stats.sort_values('total_positive_feedback', ascending=False), 
                  x='department_name', 
                  y='total_positive_feedback',
                  color='total_positive_feedback',
                  color_continuous_scale='Greens')
    fig3.update_layout(xaxis_tickangle=-45, showlegend=False)
    st.plotly_chart(fig3, use_container_width=True)

with col2:
    st.subheader("👥 Distribution des Ratings")
    rating_dist = df['rating'].value_counts().sort_index()
    fig4 = px.bar(x=rating_dist.index, 
                  y=rating_dist.values,
                  labels={'x': 'Rating', 'y': 'Nombre de Reviews'},
                  color=rating_dist.values,
                  color_continuous_scale='YlOrRd')
    st.plotly_chart(fig4, use_container_width=True)

st.divider()

# Distribution par âge
st.subheader("📊 Rating Moyen par Tranche d'Âge")
df['age_group'] = pd.cut(df['age'], bins=[0, 25, 35, 45, 55, 100], 
                         labels=['18-25', '26-35', '36-45', '46-55', '55+'])
age_stats = df.groupby('age_group')['rating'].mean().reset_index()
fig5 = px.line(age_stats, x='age_group', y='rating', markers=True)
fig5.update_layout(xaxis_title='Tranche d\'âge', yaxis_title='Rating Moyen')
st.plotly_chart(fig5, use_container_width=True)

st.divider()

# Tableau récapitulatif
st.subheader("📋 Statistiques Détaillées par Département")
dept_stats_display = dept_stats.copy()
dept_stats_display['avg_rating'] = dept_stats_display['avg_rating'].round(2)
dept_stats_display['avg_age'] = dept_stats_display['avg_age'].round(1)
dept_stats_display = dept_stats_display.sort_values('total_reviews', ascending=False)

st.dataframe(dept_stats_display.style.format({
    'total_reviews': '{:,.0f}',
    'avg_rating': '{:.2f}',
    'total_positive_feedback': '{:,.0f}',
    'avg_age': '{:.1f}'
}).background_gradient(subset=['avg_rating'], cmap='RdYlGn', vmin=1, vmax=5),
use_container_width=True)

st.divider()

# Filtres interactifs
st.subheader("🔍 Explorer les Reviews")

col1, col2, col3 = st.columns(3)
with col1:
    dept_filter = st.selectbox("Département", ['Tous'] + sorted(df['department_name'].unique().tolist()))
with col2:
    rating_filter = st.slider("Rating Minimum", 1, 5, 1)
with col3:
    age_filter = st.slider("Âge", int(df['age'].min()), int(df['age'].max()), 
                           (int(df['age'].min()), int(df['age'].max())))

# Appliquer les filtres
df_filtered = df.copy()
if dept_filter != 'Tous':
    df_filtered = df_filtered[df_filtered['department_name'] == dept_filter]
df_filtered = df_filtered[(df_filtered['rating'] >= rating_filter) & 
                          (df_filtered['age'] >= age_filter[0]) & 
                          (df_filtered['age'] <= age_filter[1])]

st.write(f"**{len(df_filtered):,} reviews** correspondent aux critères")

# Afficher quelques reviews
if len(df_filtered) > 0:
    st.subheader("💬 Exemples de Reviews")
    sample_reviews = df_filtered[['title', 'review_text', 'rating', 'department_name', 'age']].head(5)
    for idx, row in sample_reviews.iterrows():
        with st.expander(f"⭐ {row['rating']} - {row['title'][:50]}..."):
            st.write(f"**Département:** {row['department_name']}")
            st.write(f"**Âge:** {row['age']:.0f} ans")
            st.write(f"**Review:** {row['review_text'][:300]}...")
