#include "stdafx.h"
#include "EuclideanPathRenderer.h"

using namespace Glyph3;

EuclideanPathRenderer::EuclideanPathRenderer(RendererDX11& Renderer)
: m_Renderer(Renderer)
{
	ViewMatrix.MakeIdentity();
	ProjMatrix.MakeIdentity();

	m_pDiscreteSurfParam = Renderer.m_pParamMgr->GetShaderResourceParameterRef(std::wstring(_T("FullConnectedDiscretePathSurface")));

}


EuclideanPathRenderer::~EuclideanPathRenderer()
{
}


void EuclideanPathRenderer::SetTargets(
	std::vector<ResourcePtr>& renderTargets, 
	ResourcePtr DepthTarget,
	ResourcePtr DiscretePathSurface,
	int Viewport)
{
	m_renderTargets = renderTargets;
	SetViewPort(Viewport);
	m_DepthTarget = DepthTarget;
	m_DiscreteSurf = DiscretePathSurface;
}

void EuclideanPathRenderer::Update(float fTime)
{
}

void EuclideanPathRenderer::QueuePreTasks(RendererDX11* pRenderer)
{
	if (m_pEntity != NULL)
	{
		Matrix4f view = m_pEntity->Transform.GetView();
		SetViewMatrix(view);
	}

	// Queue this view into the renderer for processing.
	pRenderer->QueueTask(this);

	if (m_pScene)
	{
		// Run through the graph and pre-render the entities
		m_pScene->PreRender(pRenderer, VT_GBUFFER);
	}
}

void EuclideanPathRenderer::ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager)
{
	if (m_pScene)
	{
		// Set the parameters for rendering this view
		pPipelineManager->ClearRenderTargets();
		for (unsigned int i = 0; i < m_renderTargets.size(); ++i)
			pPipelineManager->OutputMergerStage.DesiredState.RenderTargetViews.SetState(i, m_renderTargets[i]->m_iResourceRTV);
		pPipelineManager->OutputMergerStage.DesiredState.DepthTargetViews.SetState(m_DepthTarget->m_iResourceDSV);
		pPipelineManager->ApplyRenderTargets();

		pPipelineManager->ClearBuffers(m_vColor, 1.0f);

		// Configure the desired viewports in this pipeline
		ConfigureViewports(pPipelineManager);

		// Set this view's render parameters
		SetRenderParams(pParamManager);

		// Run through the graph and render each of the entities
		m_pScene->GetRoot()->Render(pPipelineManager, pParamManager, VT_GBUFFER);
	}
}

void EuclideanPathRenderer::Resize(UINT width, UINT height)
{
}


std::wstring EuclideanPathRenderer::GetName()
{
	return(L"EuclideanPathRenderer");
}

void EuclideanPathRenderer::SetRenderParams(IParameterManager* pParamManager)
{
	pParamManager->SetViewMatrixParameter(&ViewMatrix);
	pParamManager->SetProjMatrixParameter(&ProjMatrix);
	pParamManager->SetShaderResourceParameter(m_pDiscreteSurfParam, m_DiscreteSurf);
}